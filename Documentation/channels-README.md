# ATAK Channels — channels.zip

`channels.zip` in the repository root is an **ATAK client data package** that
provides pre-configured channel definitions for use with CivTAK (ATAK) clients
connecting to this TAK Server deployment.

---

## What is an ATAK Channel?

ATAK channels are named CoT (Cursor-on-Target) data groups used to organise
which clients send and receive data from each other. Each client is assigned to
one or more channels. Traffic is routed through TAK Server based on group
membership.

Channel membership is controlled server-side in
**WebTAK → Administration → Groups** (port 8443), or via the
`TAKServerPS` module using `Get-TAKGroup`, `New-TAKGroup`, and `Set-TAKUserGroup`.

---

## Contents of channels.zip

The ZIP is a standard ATAK Data Package ([ATAK SDK Data Package spec][1]).
Typical contents:

```
channels.zip
├── MANIFEST/
│   └── manifest.xml          ← package metadata (UID, version, name)
└── atak/
    └── config/
        └── network.xml       ← channel/group definitions imported by ATAK client
```

> **To inspect the current contents** without extracting:
> ```powershell
> Add-Type -AssemblyName System.IO.Compression.FileSystem
> [System.IO.Compression.ZipFile]::OpenRead('.\channels.zip').Entries |
>     Select-Object FullName, Length
> ```

---

## Deploying channels.zip to ATAK Clients

### Option 1 — Side-load via USB / file transfer

1. Copy `channels.zip` to the Android device (e.g. `/sdcard/atak/`).
2. In ATAK, go to **Settings → Import Manager → Local SD**.
3. Select `channels.zip` and tap **Import**.

### Option 2 — Push via TAK Server data package

1. Upload `channels.zip` to the TAK Server via WebTAK:
   **Tools → Data Package → Upload**.
2. Share with the relevant groups. ATAK clients will download it automatically
   on next sync.

### Option 3 — Push via TAKServerPS

```powershell
# Connect first
Connect-TAKServer -HostName 'tak.example.com'

# Upload the data package
Send-TAKDataPackage -Path '.\channels.zip' -GroupList 'Operators'
```

---

## Updating channels.zip for a New Unit

When onboarding a new unit or changing channel assignments:

1. Extract the ZIP, edit `atak/config/network.xml` to add/rename channels.
2. Re-package:
   ```powershell
   Compress-Archive -Path .\atak, .\MANIFEST -DestinationPath .\channels.zip -Force
   ```
3. Update the `<UID>` and `<version>` in `MANIFEST/manifest.xml` so ATAK
   clients recognise the new package and re-import.
4. Commit the updated `channels.zip` and tag the release if appropriate.

---

## Server-Side Group Creation

Channels deployed via a data package must correspond to **groups** configured on
the TAK Server. To create matching groups:

```powershell
Connect-TAKServer -HostName 'tak.example.com'

# Create channel groups
New-TAKGroup -Name 'Alpha'     -Direction InOut
New-TAKGroup -Name 'Bravo'     -Direction InOut
New-TAKGroup -Name 'Intel'     -Direction In     # input-only (receive only)
New-TAKGroup -Name 'Command'   -Direction Out    # output-only (send only)

# Assign a user to a channel
Set-TAKUserGroup -UserName 'fielduser1' -GroupList 'Alpha', 'Bravo'
```

---

## Notes

- The `__ANON__` group is the TAK Server default group. All users are members
  unless explicitly removed.
- Group membership changes take effect immediately — no server restart required.
- Certificate-authenticated clients (ATAK with a `.p12` cert) are placed into
  groups by TAK Server based on the cert's Subject or via explicit assignment.

[1]: https://tak.gov/products/atak
