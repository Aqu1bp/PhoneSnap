#include "PhoneTCP.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <openssl/ssl.h>
#include <openssl/pem.h>
#include <openssl/err.h>

struct phone_tcp { int fd; SSL_CTX *context; SSL *ssl; X509 *expected; phone_tcp_is_current is_current; void *cancel_context; };

static int64_t now_ms(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static int wait_fd(int fd, short events, int64_t deadline, phone_tcp_is_current current, void *context) {
    for (;;) {
        int64_t left = deadline - now_ms();
        if (left <= 0 || (current && !current(context))) return -1;
        struct pollfd p = { .fd = fd, .events = events };
        int n = poll(&p, 1, (int)(left > 100 ? 100 : left));
        if (n < 0 && errno == EINTR) continue;
        if (n == 0) continue;
        if (n < 0 || (p.revents & (POLLERR | POLLNVAL))) return -1;
        return 0;
    }
}
phone_tcp *phone_tcp_open(const void *address, size_t length, uint16_t port, int timeout_ms,
    phone_tcp_is_current current, void *context) {
    if (!address || length < sizeof(struct sockaddr) || length > sizeof(struct sockaddr_storage) || !port) return NULL;
    struct sockaddr_storage storage = {0}; memcpy(&storage, address, length);
    struct sockaddr *sa = (struct sockaddr *)&storage;
    if (sa->sa_family == AF_INET && length == sizeof(struct sockaddr_in))
        ((struct sockaddr_in *)&storage)->sin_port = htons(port);
    else if (sa->sa_family == AF_INET6 && length == sizeof(struct sockaddr_in6))
        ((struct sockaddr_in6 *)&storage)->sin6_port = htons(port);
    else return NULL;
    int fd = socket(sa->sa_family, SOCK_STREAM, 0);
    if (fd < 0) return NULL;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0) { close(fd); return NULL; }
    int result = connect(fd, sa, (socklen_t)length);
    if (result < 0) {
        int error = 0; socklen_t size = sizeof(error);
        if (errno != EINPROGRESS || wait_fd(fd, POLLOUT, now_ms() + timeout_ms, current, context) ||
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) || error) { close(fd); return NULL; }
    }
    phone_tcp *tcp = calloc(1, sizeof(*tcp));
    if (!tcp) { close(fd); return NULL; }
    tcp->fd = fd; tcp->is_current = current; tcp->cancel_context = context;
    return tcp;
}
void phone_tcp_close(phone_tcp *tcp) {
    if (!tcp) return;
    /* No blocking TLS shutdown during cancellation or a disconnected phone. */
    if (tcp->ssl) SSL_free(tcp->ssl);
    if (tcp->context) SSL_CTX_free(tcp->context);
    if (tcp->expected) X509_free(tcp->expected);
    close(tcp->fd); free(tcp);
}
static int transfer(phone_tcp *tcp, void *bytes, size_t length, int writing, int timeout_ms) {
    if (!tcp || (!bytes && length)) return -1;
    size_t offset = 0; int64_t deadline = now_ms() + timeout_ms;
    while (offset < length) {
        if (now_ms() >= deadline || (tcp->is_current && !tcp->is_current(tcp->cancel_context))) return -1;
        size_t chunk = length - offset;
        if (chunk > INT_MAX) chunk = INT_MAX;
        int n; short events = writing ? POLLOUT : POLLIN;
        if (tcp->ssl) {
            ERR_clear_error();
            n = writing ? SSL_write(tcp->ssl, (char *)bytes + offset, (int)chunk)
                        : SSL_read(tcp->ssl, (char *)bytes + offset, (int)chunk);
            if (n <= 0) {
                int error = SSL_get_error(tcp->ssl, n);
                if (error == SSL_ERROR_WANT_READ) events = POLLIN;
                else if (error == SSL_ERROR_WANT_WRITE) events = POLLOUT;
                else return -1;
            }
        } else {
            ssize_t value = writing ? send(tcp->fd, (char *)bytes + offset, chunk, 0)
                                    : recv(tcp->fd, (char *)bytes + offset, chunk, 0);
            if (value == 0) return -1;
            if (value < 0 && errno == EINTR) continue;
            if (value < 0 && errno != EAGAIN && errno != EWOULDBLOCK) return -1;
            n = (int)value;
        }
        if (n > 0) offset += (size_t)n;
        else if (wait_fd(tcp->fd, events, deadline, tcp->is_current, tcp->cancel_context)) return -1;
    }
    return 0;
}
int phone_tcp_read(phone_tcp *tcp, void *bytes, size_t length, int timeout_ms) {
    return transfer(tcp, bytes, length, 0, timeout_ms);
}
int phone_tcp_write(phone_tcp *tcp, const void *bytes, size_t length, int timeout_ms) {
    return transfer(tcp, (void *)bytes, length, 1, timeout_ms);
}
static X509 *read_certificate(const void *data, size_t length) {
    if (!data || !length || length > INT_MAX) return NULL;
    BIO *bio = BIO_new_mem_buf(data, (int)length);
    if (!bio) return NULL;
    X509 *cert = PEM_read_bio_X509(bio, NULL, NULL, NULL); BIO_free(bio); return cert;
}
static int verify_pinned_device(X509_STORE_CTX *store, void *argument) {
    phone_tcp *tcp = argument;
    X509 *peer = X509_STORE_CTX_get0_cert(store);
    if (!peer || !tcp->expected) return 0;
    EVP_PKEY *actual = X509_get_pubkey(peer), *expected = X509_get_pubkey(tcp->expected);
    int matches = actual && expected && EVP_PKEY_eq(actual, expected) == 1;
    EVP_PKEY_free(actual); EVP_PKEY_free(expected);
    return matches;
}
int phone_tcp_start_tls(phone_tcp *tcp,
    const void *host_certificate, size_t certificate_length,
    const void *host_key, size_t key_length,
    const void *device_certificate, size_t device_length, int timeout_ms) {
    if (!tcp || tcp->ssl || !host_key || !key_length || key_length > INT_MAX) return -1;
    X509 *host = read_certificate(host_certificate, certificate_length);
    BIO *bio = BIO_new_mem_buf(host_key, (int)key_length);
    EVP_PKEY *key = bio ? PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL) : NULL;
    BIO_free(bio);
    tcp->expected = read_certificate(device_certificate, device_length);
    tcp->context = SSL_CTX_new(TLS_client_method());
    int valid = host && key && tcp->expected && tcp->context;
    if (valid) {
        /* Existing Apple pairing certificates may use legacy signature algorithms.
           TLS 1.2+ is required; identity comes from the saved public-key pin. */
        SSL_CTX_set_security_level(tcp->context, 0);
        valid = SSL_CTX_set_min_proto_version(tcp->context, TLS1_2_VERSION) == 1 &&
                SSL_CTX_use_certificate(tcp->context, host) == 1 &&
                SSL_CTX_use_PrivateKey(tcp->context, key) == 1 &&
                SSL_CTX_check_private_key(tcp->context) == 1;
    }
    X509_free(host); EVP_PKEY_free(key);
    if (!valid) return -1;
    SSL_CTX_set_verify(tcp->context, SSL_VERIFY_PEER, NULL);
    SSL_CTX_set_cert_verify_callback(tcp->context, verify_pinned_device, tcp);
    tcp->ssl = SSL_new(tcp->context);
    if (!tcp->ssl || SSL_set_fd(tcp->ssl, tcp->fd) != 1) return -1;
    int64_t deadline = now_ms() + timeout_ms;
    for (;;) {
        if (tcp->is_current && !tcp->is_current(tcp->cancel_context)) return -1;
        ERR_clear_error();
        int n = SSL_connect(tcp->ssl);
        if (n == 1) return 0;
        int error = SSL_get_error(tcp->ssl, n);
        short events;
        if (error == SSL_ERROR_WANT_READ) events = POLLIN;
        else if (error == SSL_ERROR_WANT_WRITE) events = POLLOUT;
        else return -1;
        if (wait_fd(tcp->fd, events, deadline, tcp->is_current, tcp->cancel_context)) return -1;
    }
}
