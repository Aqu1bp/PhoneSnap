#include <stddef.h>
#include <stdint.h>

typedef struct phone_tcp phone_tcp;
typedef int (*phone_tcp_is_current)(void *context);
/* All operations have an absolute timeout. Addresses are resolved sockaddr bytes. */
phone_tcp *phone_tcp_open(const void *address, size_t length, uint16_t port, int timeout_ms,
    phone_tcp_is_current is_current, void *context);
int phone_tcp_read(phone_tcp *tcp, void *bytes, size_t length, int timeout_ms);
int phone_tcp_write(phone_tcp *tcp, const void *bytes, size_t length, int timeout_ms);
/* Authenticate the server against the saved device certificate's public key.
   PEM credentials are held only in memory; no files or keychain entries are created. */
int phone_tcp_start_tls(phone_tcp *tcp,
    const void *host_certificate, size_t certificate_length,
    const void *host_key, size_t key_length,
    const void *device_certificate, size_t device_length, int timeout_ms);
void phone_tcp_close(phone_tcp *tcp);
