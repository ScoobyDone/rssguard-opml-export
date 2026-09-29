### 99% done by chatgpt
v6 astra medium.
i spent 5 minutes writing the prompt.
it spent 5 minutes writing it out.
i spent 5 minutes reviewing it and didn't see anything worth spending more time on it.
i ran it twice and it worked both times just fine
enjoy.


# RSS Guard database â OPML

External exporters that take `database.db` as an argument and write OPML to stdout.
They do not launch RSS Guard, change its database, fetch URLs, or execute stored
feed scripts. Diagnostics go to stderr; failure returns a nonzero exit code.

## Files and requirements

| File | Requirements |
|---|---|
| `rssguard-opml.pseudocode.txt` | Language-neutral algorithm |
| `rssguard-opml.py` | Python 3.9+; standard library only |
| `rssguard-opml.sh` | Bash, sqlite3 CLI 3.33+ with JSON support, jq 1.6+ |
| `rssguard-opml.ps1` | PowerShell 5.1+ and sqlite3 CLI 3.33+ with JSON support |
| `backup-rssguard.sh` | Scheduled Linux wrapper; uses Python exporter by default |
| `backup-rssguard.cmd` | Scheduled Windows wrapper; uses Python exporter |

The three implementations are independent. Python is the simplest to install
because it includes its SQLite interface. Bash and PowerShell need the SQLite
command-line executable on PATH (or PowerShell's `-Sqlite` argument).

## Usage

All exporters accept an optional second argument: a numeric account ID.
Without it, **all feeds and categories from all accounts** are exported. With it,
only that account is exported. Unknown account IDs fail instead of producing an
empty, apparently successful backup.

Bash/Linux (choose one exporter per run):

```bash
stamp=$(date '+%Y-%m-%d_%H-%M-%S')
# A subshell keeps noclobber local to this invocation.
(set -o noclobber; python3 ./rssguard-opml.py '/path/to/database.db' > "subscriptions_${stamp}.opml")

# Alternative: Bash exporter, with its own timestamp.
stamp=$(date '+%Y-%m-%d_%H-%M-%S')
(set -o noclobber; bash ./rssguard-opml.sh '/path/to/database.db' > "subscriptions_${stamp}.opml")

# Export only account 1:
stamp=$(date '+%Y-%m-%d_%H-%M-%S')
(set -o noclobber; python3 ./rssguard-opml.py '/path/to/database.db' 1 > "account-1_${stamp}.opml")
```

`$(date '+%Y-%m-%d_%H-%M-%S')` is the Bash command substitution syntax.
GNU `date --date='now' '+%Y-%m-%d_%H-%M-%S'` also works, but `--date='now'`
is unnecessary: the default is already the current time. Only one `$()` is needed.

Windows PowerShell 5.1 or PowerShell 7:

```powershell
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
.\rssguard-opml.ps1 'C:\RSSGuard\data\database.db' -Sqlite 'C:\Tools\sqlite3.exe' |
    Out-File -LiteralPath ".\subscriptions_$stamp.opml" -Encoding utf8 -NoClobber
```

`HH` means 24-hour hours and `mm` means minutes in PowerShell's format;
`MM` means month. Bash uses `%H`, `%M`, and `%m`, respectively.
Use explicit `Out-File -Encoding utf8` in **Windows PowerShell 5.1**: its default
`>` encoding is UTF-16LE, which would disagree with the XML's UTF-8 declaration.
The UTF-8 BOM produced by 5.1's `Out-File` is valid XML.

From Windows Command Prompt, use the included wrapper after editing its paths:

```bat
C:\Scripts\backup-rssguard.cmd
```

It uses PowerShell to obtain the timestamp and Python to generate the OPML,
with byte-preserving native redirection. No Python-to-PowerShell text pipeline
is involved.

Example filename: `subscriptions_2026-09-28_17-58-58.opml`. The timestamp is
**local time at the start of the run**; the OPML `dateCreated` remains UTC.
Second-resolution timestamps can still collide (simultaneous runs, repeated
clock times, or reruns within the same second). The examples use Bash `noclobber`
or PowerShell `-NoClobber`; the scheduled wrappers also refuse to overwrite an
existing destination. A collision fails rather than replacing an earlier export.
Wait for a new timestamp and rerun if that happens.

The short examples can leave an empty/new output file if export fails. The
scheduled wrappers generate a temporary file first and publish it only after
successful export. They retain dated exports; they no longer maintain a single
`subscriptions.opml`, and there is no automatic retention/deletion policy.
Always use a separate `.opml` destination, never the database path.

To inspect account IDs without changing the database (SQLite CLI required):

```bash
sqlite3 -readonly -header -column '/path/to/database.db' 'SELECT id, type, ordr FROM Accounts ORDER BY ordr, id;'
```

## Match to RSS Guard's export

Verified against RSS Guard tag **4.8.6** and development commit
`77cb8438620d1593fed9e027c05ed8294f000d05` (checked 2026-09-28).
The common columns used here exist in both schemas. Unsupported schemas fail
with a database error instead of guessing column names.

For standard `std-rss` accounts, this reproduces the **OPML structure and fields**
of the built-in exporter with icons disabled:

- XML declaration, OPML 2.0, RSS Guard namespace, title, UTC creation date.
- Nested category outlines, including empty folders and descriptions.
- Feed `type="rss"`, `text`, `title`, `xmlUrl`, `description`, and `encoding`.
- `rssguard:xmlUrlType`, `rssguard:postProcess`, and applicable `version` values.
- Root items use category/parent ID `-1`; feed metadata comes from JSON in
  `Feeds.custom_data`, not assumed standalone columns.

For other service account types, the scripts export generic feed/category
outlines from the locally stored rows. They cannot recreate service-specific
export behavior or recover remote subscriptions that are absent from the database.

This is not a byte-for-byte copy of Qt's serializer: attribute ordering, empty
folder formatting, namespace placement, and escaping can differ. Output uses
stored `ordr` values, with deterministic category/feed/ID tie-breakers; it does
not reproduce an active GUI alphabetical sort. Multiple accounts share the OPML
body without synthetic account folders, so account identity is lost. Select one
account for the closest correspondence to an in-app export.

Icons, articles, read status, credentials, and other non-OPML application settings
are not exported. Stored script/local-file sources and post-processing strings
are preserved as text, exactly as metadata, without running them. URLs or scripts
can themselves contain private values, so handle the output like your in-app OPML.

The exporters open SQLite read-only, wait up to 10 seconds for a database lock,
and read a consistent snapshot. They can read a live database, including committed
WAL changes, provided SQLite can access the database and any required `-wal`/`-shm`
files. Do not copy only `database.db` while RSS Guard is writing in WAL mode.
Close RSS Guard first if your filesystem permissions prevent live read-only access.
Unsaved in-memory application changes are not available to an external exporter.

Orphaned rows, unreachable folder cycles, excessive nesting (>200 levels), malformed
standard-feed JSON, and invalid XML characters fail without partial OPML output.
An empty database with valid tables produces a valid empty OPML document.

## Windows Task Scheduler example: daily at 02:00

1. Put `rssguard-opml.py` and `backup-rssguard.cmd` in `C:\Scripts`.
2. Edit the four paths in `backup-rssguard.cmd`, including the actual `python.exe`
   location. Create `C:\Backups\RSSGuard` first.
3. Run the wrapper once from Command Prompt, inspect the new `subscriptions_YYYY-MM-DD_HH-MM-SS.opml`, and
   check the exit code immediately afterward:

   ```bat
   C:\Scripts\backup-rssguard.cmd
   echo %ERRORLEVEL%
   ```

4. In Task Scheduler, create a task with a daily trigger at **02:00**.
   Use an account with access to the database and output directory.

   | Action field | Value |
   |---|---|
   | Program/script | `C:\Windows\System32\cmd.exe` |
   | Add arguments | `/d /c C:\Scripts\backup-rssguard.cmd` |
   | Start in | `C:\Scripts` |

5. Select âRun whether user is logged on or notâ if desired, âRun task as soon as
   possible after a scheduled start is missed,â and âDo not start a new instance.â
   Use **Run** once and check Last Run Result: `0x0` means success.

The wrapper sends exporter errors to `C:\Backups\RSSGuard\export-errors.log` and
creates `subscriptions_YYYY-MM-DD_HH-MM-SS.opml` only after the exporter exits
successfully. Windows PowerShell's two-argument `[IO.File]::Move` refuses to
replace an existing destination, so a collision is logged and returns exit 1.
The temporary file is uniquely created by `[IO.Path]::GetTempFileName()` and is
removed if export or publication fails. No scheduled task has been installed
by this package.

## cron example: daily at 02:00

Put `rssguard-opml.py` and `backup-rssguard.sh` together in
`/home/harry/bin/rssguard-opml`. Edit the database and output paths in the wrapper,
and create `/home/harry/backups/rssguard` first. Run it once:

```bash
/bin/bash /home/harry/bin/rssguard-opml/backup-rssguard.sh
```

Use `crontab -e` for the account that can read RSS Guard's database; add:

```cron
PATH=/usr/local/bin:/usr/bin:/bin
0 2 * * * /bin/bash /home/harry/bin/rssguard-opml/backup-rssguard.sh 2>>/home/harry/backups/rssguard/export-errors.log
```

This runs daily at 02:00 in cron's configured timezone. The wrapper creates a
private temporary file in the destination directory, then publishes it as
`subscriptions_YYYY-MM-DD_HH-MM-SS.opml` after success. GNU `ln -T` creates the
final name without overwriting an existing path; the temporary name is then
removed. This requires GNU coreutils and a destination filesystem supporting
hard links (for example ext4; FAT/exFAT do not). Collisions and publication errors
return nonzero and appear in the error log. The comment in the wrapper shows how
to substitute the Bash exporter. The output directory must exist before cron runs.
No cron entry has been installed by this package.

The timestamp command stays inside the wrapper, so its `%` characters need no
special cron escaping. If you put `date` directly in a crontab command, escape
each `%` as `\%`, even inside quotes. For example, this shorter alternative uses
the Python exporter and refuses overwrite, but can leave an empty output on failure:

```cron
0 2 * * * /bin/bash -c 'set -o noclobber; /usr/bin/python3 /home/harry/bin/rssguard-opml/rssguard-opml.py /home/harry/rssguard-data/database.db > "/home/harry/backups/rssguard/subscriptions_$(date +\%Y-\%m-\%d_\%H-\%M-\%S).opml"' 2>>/home/harry/backups/rssguard/export-errors.log
```

Choose either the wrapper cron entry or this alternative, not both.

## Validation and limits

All three exporters were executed on synthetic databases using Python 3.12,
Bash, sqlite3 3.45, jq 1.7, and PowerShell 7.4.6 on Linux. Thirty-three executions
covered equal parsed XML across implementations, nested/empty folders, all mapped
feed types, Unicode, XML metacharacters, newlines/tabs in attributes, multiple
accounts, account filtering, committed WAL data, unchanged database bytes,
missing paths, malformed JSON, invalid XML characters, and orphan/cyclic folders.
Bash also passed `bash -n` and ShellCheck. The timestamp update was additionally
checked for successful publication, same-second collision refusal, and exporter
failure cleanup in the Linux wrapper. PowerShell timestamp formatting,
`Out-File -NoClobber`, and two-argument `File.Move` collision refusal were tested
with PowerShell 7 on Linux.

The user's actual database was not provided. Windows PowerShell 5.1 and the
Windows batch/Task Scheduler examples were reviewed but could not be executed in
this Linux environment. Cron syntax was checked against its documentation; no
scheduler was installed or waited on. Import through the RSS Guard GUI was not
run; compatibility is based on source inspection and XML validation.

## Sources

- [RSS Guard exporter, pinned commit](https://github.com/martinrotter/rssguard/blob/77cb8438620d1593fed9e027c05ed8294f000d05/src/librssguard-standard/src/standardfeedsimportexportmodel.cpp)
- [Current database schema, pinned commit](https://github.com/martinrotter/rssguard/blob/77cb8438620d1593fed9e027c05ed8294f000d05/resources/sql/db_init.sql)
- [RSS Guard 4.8.6 SQLite schema](https://github.com/martinrotter/rssguard/blob/4.8.6/resources/sql/db_init_sqlite.sql)
- [Standard feed metadata and enum definitions](https://github.com/martinrotter/rssguard/blob/77cb8438620d1593fed9e027c05ed8294f000d05/src/librssguard-standard/src/standardfeed.h)
- [SQLite CLI](https://www.sqlite.org/cli.html)
- [Python sqlite3](https://docs.python.org/3/library/sqlite3.html)
- [PowerShell redirection](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection)
- [Microsoft: Task Scheduler actions](https://learn.microsoft.com/en-us/windows/win32/taskschd/actions)
- [crontab format](https://man7.org/linux/man-pages/man5/crontab.5.html)

