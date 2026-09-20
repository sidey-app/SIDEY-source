import windowsRelease from "../../../release/windows.json";

export const appStoreURL = "https://apps.apple.com/kr/app/sidey/id6808528060?mt=12";

export const releases = {
  macos: {
    url: appStoreURL,
  },
  windows: {
    version: windowsRelease.version,
    url: `https://github.com/sidey-app/SIDEY/releases/download/windows-v${windowsRelease.version}/SIDEY-Windows-x64-v${windowsRelease.version}-Setup.exe`,
    notes: `https://github.com/sidey-app/SIDEY/releases/tag/windows-v${windowsRelease.version}`,
    // Local-preview fallback. Pages replaces it with the verified release asset hash.
    sha256: "269a9f292fffd9e1a1ee205fe068b82f2a16d798eb4e64bd9025f8157d0fa0fb",
  },
} as const;
