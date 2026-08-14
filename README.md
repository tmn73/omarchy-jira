# Omarchy Jira

Your Jira work, in the Omarchy bar.

Tickets assigned to you, separated into what is waiting on you and what is
merely assigned, plus search across your whole site by issue key or summary.
Click a ticket to open it.

This is not a Jira client. It answers two questions: what is on my plate right
now, and where is ticket X.

## Requirements

- Omarchy Quattro with shell plugin support
- `curl`, `jq`, and `secret-tool`, all installed by Omarchy already
- A Nerd Font, which Omarchy includes by default

## Install

```bash
omarchy plugin add https://github.com/tmn73/omarchy-jira.git --enable
./omarchy-jira-auth
```

The setup asks for your site, your account email, and an
[API token](https://id.atlassian.com/manage-profile/security/api-tokens),
verifies them against Jira before storing anything, and puts the token in your
system keyring.

## Credentials

The token lives in the system keyring, under `service=omarchy-jira`. The plugin
reads it at request time and never copies, logs, caches, or writes it anywhere.
Nothing lands in `shell.json` or in a dotfile, and no credential is ever typed
into a bar popup.

## Local development

```bash
omarchy plugin validate .
omarchy plugin add "$PWD" --enable
```

The shell watches local plugin files, so QML iteration is fast.

## License

MIT
