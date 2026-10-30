# Who may SSH where

One file per target host (`pi`, `aws`, `mac`), containing the `authorized_keys`
lines for the `starsi` tunnel user on that host. This directory is the committed
source of truth; `distribute-authorized-keys.sh` pushes it out. Never hand-edit
`~starsi/.ssh/authorized_keys` on a machine.

Every entry must carry forwarding-only restrictions, e.g. for the phone on `aws`:

```
restrict,port-forwarding,permitopen="127.0.0.1:30086",permitopen="127.0.0.1:18484" ssh-ed25519 AAAA... starsi-iphone
```

- `restrict` — no pty, no agent/X11 forwarding, no exec
- `permitopen` — only the enumerated loopback NodePorts / tunnel ports
- machine keys (`pi`→`aws` autossh) additionally need
  `permitlisten="127.0.0.1:18484"` for the reverse tunnel

Host keys are pinned: `known_hosts` in this directory is pushed to every
machine and bundled into the iOS app. Regenerate it with
`ssh-keyscan -t ed25519 <host>` when a machine is reinstalled.
