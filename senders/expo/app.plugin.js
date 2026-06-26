const { withInfoPlist } = require('@expo/config-plugins');

module.exports = function withPhoneSnapSender(config) {
  return withInfoPlist(config, (mod) => {
    mod.modResults.NSLocalNetworkUsageDescription =
      mod.modResults.NSLocalNetworkUsageDescription ||
      'Debug builds can send UI snapshots to PhoneSnap on your Mac.';

    const ats = mod.modResults.NSAppTransportSecurity || {};
    ats.NSAllowsLocalNetworking = true;
    mod.modResults.NSAppTransportSecurity = ats;

    return mod;
  });
};
