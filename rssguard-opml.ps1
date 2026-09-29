#Requires -Version 5.1
<# Independent PowerShell implementation; requires sqlite3 >= 3.33 with JSON.
Usage: .\rssguard-opml.ps1 C:\path\database.db [account-id]
Outputs one XML string to the success stream. Errors go to stderr; exit 1.
Windows PowerShell 5.1: use Out-File -Encoding utf8, not bare >.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)][string]$Database,
    [Parameter(Position=1)][Nullable[int]]$AccountId,
    [string]$Sqlite = 'sqlite3'
)
$ErrorActionPreference = 'Stop'
try {
    $db = (Get-Item -LiteralPath $Database -ErrorAction Stop).FullName
    if (-not [IO.File]::Exists($db)) { throw 'Database path is not a file' }
    $null = Get-Command $Sqlite -ErrorAction Stop
    $sql = @'
SELECT json_object(
 'accounts', (SELECT json_group_array(json_object('id',id,'ordr',ordr,'type',type)) FROM Accounts),
 'categories', (SELECT json_group_array(json_object('id',id,'ordr',ordr,'parent',parent_id,'title',title,'description',description,'account_id',account_id)) FROM Categories),
 'feeds', (SELECT json_group_array(json_object('id',id,'ordr',ordr,'parent',category,'title',title,'description',description,'source',source,'custom_data',custom_data,'account_id',account_id)) FROM Feeds)
);
'@
    $oldEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $nullDevice = if ($env:OS -eq 'Windows_NT') { 'NUL' } else { '/dev/null' }
        $raw = & $Sqlite -init $nullDevice -batch -bail -readonly -noheader -list -cmd '.timeout 10000' $db $sql
        if ($LASTEXITCODE -ne 0) { throw "sqlite3 failed (exit $LASTEXITCODE)" }
    } finally { [Console]::OutputEncoding = $oldEncoding }
    $data = ($raw -join "`n") | ConvertFrom-Json
    $accounts = @($data.accounts)
    $cats = @($data.categories)
    $feeds = @($data.feeds)
    if ($null -ne $AccountId) {
        $accounts = @($accounts | Where-Object { $_.id -eq $AccountId })
        if ($accounts.Count -eq 0) { throw 'Account ID not found' }
        $cats = @($cats | Where-Object { $_.account_id -eq $AccountId })
        $feeds = @($feeds | Where-Object { $_.account_id -eq $AccountId })
    }
    $doc = [Xml.XmlDocument]::new()
    $null = $doc.AppendChild($doc.CreateXmlDeclaration('1.0','UTF-8','yes'))
    $root = $doc.CreateElement('opml')
    $root.SetAttribute('version','2.0')
    $ns = 'https://github.com/martinrotter/rssguard'
    $root.SetAttribute('xmlns:rssguard',$ns)
    $null = $doc.AppendChild($root)
    $head = $doc.CreateElement('head'); $null = $root.AppendChild($head)
    $title = $doc.CreateElement('title'); $title.InnerText = 'RSS Guard'; $null = $head.AppendChild($title)
    $date = $doc.CreateElement('dateCreated')
    $date.InnerText = [DateTime]::UtcNow.ToString('r',[Globalization.CultureInfo]::InvariantCulture)
    $null = $head.AppendChild($date)
    $body = $doc.CreateElement('body'); $null = $root.AppendChild($body)
    $versions = @{0='RSS';1='RSS';2='RSS1';3='ATOM';4='JSON';5='Sitemap';9='MediaWiki'}
    $visited = [Collections.Generic.HashSet[string]]::new()
    function Add-Children($Account, [int]$Parent, [Xml.XmlElement]$Element, [int]$Depth) {
        if ($Depth -gt 200) { throw 'Folder nesting exceeds 200 levels' }
        $rows = @(
            foreach ($r in $cats) {
                if ($r.account_id -eq $Account.id -and $r.parent -eq $Parent) {
                    [pscustomobject]@{Kind='c';Row=$r}
                }
            }
            foreach ($r in $feeds) {
                if ($r.account_id -eq $Account.id -and $r.parent -eq $Parent) {
                    [pscustomobject]@{Kind='f';Row=$r}
                }
            }
        )
        foreach ($item in ($rows | Sort-Object @{Expression={$_.Row.ordr}},Kind,@{Expression={$_.Row.id}})) {
            $r = $item.Row
            if (-not $visited.Add("$($item.Kind):$($r.account_id):$($r.id)")) { throw 'Duplicate/cyclic folder or feed' }
            $node = $doc.CreateElement('outline')
            $node.SetAttribute('text',[string]$r.title)
            $node.SetAttribute('description',[string]$r.description)
            if ($item.Kind -eq 'f') {
                $node.SetAttribute('type','rss')
                $node.SetAttribute('title',[string]$r.title)
                $node.SetAttribute('xmlUrl',[string]$r.source)
                if ($Account.type -eq 'std-rss') {
                    $custom = if ([string]::IsNullOrEmpty($r.custom_data)) { '{}' } else { $r.custom_data }
                    $m = ConvertFrom-Json -InputObject $custom
                    if ($null -eq $m -or $m -isnot [pscustomobject]) { throw 'Feed custom_data must be a JSON object' }
                    $node.SetAttribute('encoding',[string]$m.encoding)
                    foreach ($pair in @(@('xmlUrlType',[string][int]$m.source_type), @('postProcess',[string]$m.post_process))) {
                        $attr = $doc.CreateAttribute('rssguard',$pair[0],$ns)
                        $attr.Value = $pair[1]; $null = $node.Attributes.Append($attr)
                    }
                    $version = $versions[[int]$m.type]
                    if ($version) { $node.SetAttribute('version',$version) }
                }
            }
            $null = $Element.AppendChild($node)
            if ($item.Kind -eq 'c') { Add-Children $Account $r.id $node ($Depth + 1) }
        }
    }
    foreach ($a in ($accounts | Sort-Object ordr,id)) { Add-Children $a -1 $body 0 }
    if ($visited.Count -ne ($cats.Count + $feeds.Count)) { throw 'Orphaned rows or cyclic folders: export refused' }
    $buffer = [IO.MemoryStream]::new()
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = "`n"
    $settings.NewLineHandling = [Xml.NewLineHandling]::Entitize
    $writer = [Xml.XmlWriter]::Create($buffer,$settings)
    try { $doc.Save($writer); $writer.Flush(); $result = [Text.Encoding]::UTF8.GetString($buffer.ToArray()) }
    finally { $writer.Dispose(); $buffer.Dispose() }
    Write-Output $result
} catch {
    [Console]::Error.WriteLine("rssguard-opml: " + $_.Exception.Message)
    exit 1
}
