param([int]$Port = 8085, [string]$Address = 'localhost')

$core = (Resolve-Path (Join-Path $PSScriptRoot '..' 'PowerBGP' 'PowerBGP.psd1')).Path

Start-PodeServer {
    Add-PodeEndpoint -Address $Address -Port $Port -Protocol Http
    Import-PodeModule -Name Pode.Web
    Import-PodeModule -Path $core

    Enable-PodeOpenApi -Path '/docs/openapi' -OpenApiVersion '3.0.3' -DisableMinimalDefinitions -NoDefaultResponses
    Add-PodeOAInfo -Title 'PowerBGP API' -Version '0.5.0' -Description 'REST API for the PowerBGP test peers (BGP and BFD). Lab use only: there is no authentication.' -LicenseName 'MIT' -LicenseUrl 'https://opensource.org/license/mit'
    Enable-PodeOpenApiViewer -Type Swagger -Path '/docs/swagger' -DarkMode
    Enable-PodeOpenApiViewer -Type ReDoc -Path '/docs/redoc' -DarkMode

    # REST API
    Add-PodeRoute -Method Get -Path '/api/bgp/peers' -ScriptBlock {
        Write-PodeJsonResponse -Value @(Get-BgpSession)
    }
    Add-PodeRoute -Method Get -Path '/api/bgp/peers/:name/routes' -ScriptBlock {
        try {
            $dir = if ($WebEvent.Query['direction']) { $WebEvent.Query['direction'] } else { 'Learned' }
            Write-PodeJsonResponse -Value @(Get-BgpRoute -Name $WebEvent.Parameters['name'] -Direction $dir)
        }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Get -Path '/api/bgp/events' -ScriptBlock {
        Write-PodeJsonResponse -Value @(Get-BgpEvent -Last 100 | Select-Object Time, Peer, Direction, Type, Summary)
    }
    Add-PodeRoute -Method Get -Path '/api/bfd/sessions' -ScriptBlock {
        Write-PodeJsonResponse -Value @(Get-BfdSession)
    }
    Add-PodeRoute -Method Post -Path '/api/bfd/sessions' -ScriptBlock {
        try {
            $d = $WebEvent.Data
            $p = @{ RemoteAddress = [string]$d.RemoteAddress }
            if ($d.Name) { $p.Name = [string]$d.Name }
            if ($d.Port) { $p.Port = [int]$d.Port }
            if ($d.ListenPort) { $p.ListenPort = [int]$d.ListenPort }
            if ($d.LocalAddress) { $p.LocalAddress = [ipaddress][string]$d.LocalAddress }
            if ($d.MultiHop -eq $true) { $p.MultiHop = $true }
            if ($d.TxMs) { $p.DesiredMinTxMs = [uint32]$d.TxMs }
            if ($d.RxMs) { $p.RequiredMinRxMs = [uint32]$d.RxMs }
            Write-PodeJsonResponse -Value (Start-BfdSession @p) -StatusCode 201
        }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Post -Path '/api/bfd/sessions/:name/stop' -ScriptBlock {
        Stop-BfdSession -Name $WebEvent.Parameters['name']
        Set-PodeResponseStatus -Code 202
    }
    Add-PodeRoute -Method Post -Path '/api/bfd/sessions/:name/resume' -ScriptBlock {
        try { Write-PodeJsonResponse -Value (Resume-BfdSession -Name $WebEvent.Parameters['name'] -ErrorAction Stop) }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Delete -Path '/api/bfd/sessions/:name' -ScriptBlock {
        Remove-BfdSession -Name $WebEvent.Parameters['name'] -Confirm:$false
        Set-PodeResponseStatus -Code 204
    }
    Add-PodeRoute -Method Put -Path '/api/bfd/sessions/:name' -ScriptBlock {
        try {
            $d = $WebEvent.Data
            $p = @{ Name = $WebEvent.Parameters['name'] }
            if ($d.Port) { $p.Port = [int]$d.Port }
            if ($d.ListenPort) { $p.ListenPort = [int]$d.ListenPort }
            if ($d.LocalAddress) { $p.LocalAddress = [ipaddress][string]$d.LocalAddress }
            if ($d.TxMs) { $p.DesiredMinTxMs = [uint32]$d.TxMs }
            if ($d.RxMs) { $p.RequiredMinRxMs = [uint32]$d.RxMs }
            if ($d.DetectMult) { $p.DetectMult = [int]$d.DetectMult }
            Write-PodeJsonResponse -Value (Update-BfdSession @p)
        }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Put -Path '/api/bgp/peers/:name' -ScriptBlock {
        try {
            $d = $WebEvent.Data
            $p = @{ Name = $WebEvent.Parameters['name'] }
            foreach ($k in 'RemoteAS', 'LocalAS') { if ($d.$k) { $p[$k] = [uint32]$d.$k } }
            if ($d.RouterId) { $p.RouterId = [ipaddress]$d.RouterId }
            if ($d.HoldTime) { $p.HoldTime = [uint16]$d.HoldTime }
            if ($d.Port) { $p.Port = [int]$d.Port }
            if ($null -ne $d.AutoReconnect) { $p.AutoReconnect = [bool]$d.AutoReconnect }
            if ($d.Password) { $p.Password = [string]$d.Password }
            if ($d.LocalAddress) { $p.LocalAddress = [string]$d.LocalAddress }
            if ($d.AddressFamily) { $p.AddressFamily = [string[]]@($d.AddressFamily) }
            if ($d.InboundFilter) { $p.InboundFilter = @($d.InboundFilter) }
            if ($d.InboundDefault) { $p.InboundDefault = [string]$d.InboundDefault }
            Write-PodeJsonResponse -Value (Update-BgpSession @p)
        }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Post -Path '/api/bgp/peers' -ScriptBlock {
        try {
            $d = $WebEvent.Data
            $p = @{ LocalAS = [uint32]$d.LocalAS; RouterId = [ipaddress]$d.RouterId }
            foreach ($k in 'Name', 'RemoteAddress') { if ($d.$k) { $p[$k] = [string]$d.$k } }
            if ($d.RemoteAS) { $p.RemoteAS = [uint32]$d.RemoteAS }
            if ($d.Port) { $p.Port = [int]$d.Port }
            if ($d.HoldTime) { $p.HoldTime = [uint16]$d.HoldTime }
            if ($d.Passive) { $p.Passive = $true }
            if ($null -ne $d.AutoReconnect) { $p.AutoReconnect = [bool]$d.AutoReconnect }
            if ($d.Password) { $p.Password = [string]$d.Password }
            if ($d.LocalAddress) { $p.LocalAddress = [ipaddress]$d.LocalAddress }
            if ($d.AddressFamily) { $p.AddressFamily = [string[]]@($d.AddressFamily) }
            if ($d.InboundFilter) { $p.InboundFilter = @($d.InboundFilter) }
            if ($d.InboundDefault) { $p.InboundDefault = [string]$d.InboundDefault }
            $peer = Start-BgpSession @p
            if ($d.UseBfd -and $d.RemoteAddress) {
                $null = Start-BfdSession -RemoteAddress ([string]$d.RemoteAddress) -Name "bfd-$($peer.Name)"
            }
            Write-PodeJsonResponse -Value $peer -StatusCode 201
        }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Delete -Path '/api/bgp/peers/:name' -ScriptBlock {
        Remove-BgpSession -Name $WebEvent.Parameters['name'] -Confirm:$false
        Set-PodeResponseStatus -Code 204
    }
    Add-PodeRoute -Method Post -Path '/api/bgp/peers/:name/stop' -ScriptBlock {
        Stop-BgpSession -Name $WebEvent.Parameters['name']
        Set-PodeResponseStatus -Code 202
    }
    Add-PodeRoute -Method Post -Path '/api/bgp/peers/:name/resume' -ScriptBlock {
        try { Write-PodeJsonResponse -Value (Resume-BgpSession -Name $WebEvent.Parameters['name'] -ErrorAction Stop) }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }
    Add-PodeRoute -Method Post -Path '/api/bgp/peers/:name/update' -ScriptBlock {
        try {
            $d = $WebEvent.Data
            $p = @{ Name = $WebEvent.Parameters['name'] }
            if ($d.Nlri) { $p.Nlri = [string[]]@($d.Nlri) }
            if ($d.Withdrawn) { $p.Withdrawn = [string[]]@($d.Withdrawn) }
            if ($d.NextHop) { $p.NextHop = [ipaddress]$d.NextHop }
            if ($d.AsPath) { $p.AsPath = [uint32[]]@($d.AsPath) }
            Send-BgpUpdate @p
            Set-PodeResponseStatus -Code 202
        }
        catch { Write-PodeJsonResponse -Value @{ error = $_.Exception.Message } -StatusCode 400 }
    }

    # OpenAPI documentation (served at /docs/openapi, /docs/swagger and /docs/redoc)
    $str = { param($n, $d) New-PodeOAStringProperty -Name $n -Description $d }
    $int = { param($n, $d) New-PodeOAIntProperty -Name $n -Description $d }
    $bool = { param($n, $d) New-PodeOABoolProperty -Name $n -Description $d }

    Add-PodeOAComponentSchema -Name 'Error' -Component (New-PodeOAObjectProperty -Properties @(& $str 'error' 'What went wrong'))
    Add-PodeOAComponentSchema -Name 'FilterRule' -Component (New-PodeOAObjectProperty -Description 'Inbound route filter rule. First match wins.' -Properties @(
            (New-PodeOAStringProperty -Name 'Action' -Enum 'Permit', 'Deny' -Required)
            (& $str 'Prefix' 'IPv4 or IPv6 prefix, e.g. 10.0.0.0/8 or 2001:db8::/32')
            (& $int 'Ge' 'Minimum prefix length (with Prefix)')
            (& $int 'Le' 'Maximum prefix length (with Prefix)')
            (& $int 'AsPathContains' 'Match when this AS is in the AS_PATH')
            (& $str 'Community' 'Match a community, e.g. 65000:100')))
    Add-PodeOAComponentSchema -Name 'Peer' -Component (New-PodeOAObjectProperty -Properties @(
            (& $str 'Name' 'Session name')
            (New-PodeOAStringProperty -Name 'State' -Enum 'Idle', 'Connect', 'Active', 'OpenSent', 'OpenConfirm', 'Established', 'Stopped')
            (New-PodeOAStringProperty -Name 'Mode' -Enum 'Active', 'Passive')
            (& $str 'Remote' 'Remote endpoint (address:port)')
            (& $str 'RemoteAddress' 'Remote address')
            (& $str 'LocalAddress' 'Local source address in use or configured')
            (& $str 'AddressFamily' 'Advertised address families, comma separated (IPv4, IPv6)')
            (& $int 'LocalAS' 'Local AS')
            (& $int 'PeerAS' 'AS the peer announced')
            (& $str 'RouterId' 'Local BGP identifier')
            (& $str 'PeerRouterId' 'Peer BGP identifier')
            (& $int 'HoldTime' 'Negotiated hold time in seconds')
            (& $str 'Uptime' 'Time since Established (d.hh:mm:ss)')
            (& $int 'Sent' 'Messages sent')
            (& $int 'Received' 'Messages received')
            (& $int 'Learned' 'Routes learned and accepted')
            (& $int 'Filtered' 'Routes dropped by the inbound filter')
            (& $int 'Advertised' 'Routes we advertise')
            (& $bool 'KeepalivesPaused' 'Fault injection: keepalives suppressed')
            (& $bool 'AutoReconnect' 'Reconnect after the session drops')
            (& $bool 'Md5' 'TCP-MD5 password configured')
            (& $int 'Reconnects' 'Reconnect attempts')
            (& $str 'NextRetry' 'Time of the next reconnect attempt')
            (& $str 'LastError' 'Last error, if any')))
    $peerSettings = @(
        (& $int 'RemoteAS' 'Expected remote AS')
        (& $int 'LocalAS' 'Local AS')
        (& $str 'RouterId' 'Local BGP identifier (IPv4 format)')
        (& $int 'HoldTime' 'Hold time in seconds')
        (& $int 'Port' 'TCP port (default 179)')
        (& $bool 'AutoReconnect' 'Reconnect after the session drops (default true)')
        (& $str 'Password' 'TCP-MD5 password (Linux only)')
        (& $str 'LocalAddress' 'Bind to this source address')
        (New-PodeOAStringProperty -Name 'AddressFamily' -Enum 'IPv4', 'IPv6' -Array -Description 'Address families to advertise (default IPv4)')
        (New-PodeOASchemaProperty -Name 'InboundFilter' -Reference 'FilterRule' -Array)
        (New-PodeOAStringProperty -Name 'InboundDefault' -Enum 'Permit', 'Deny' -Description 'Action for routes no rule matches (default Permit)'))
    Add-PodeOAComponentSchema -Name 'PeerCreate' -Component (New-PodeOAObjectProperty -Properties (@(
                (& $str 'Name' 'Session name (defaults to the remote address)')
                (& $str 'RemoteAddress' 'Remote address; required unless Passive')
                (& $bool 'Passive' 'Listen instead of connecting')
                (& $bool 'UseBfd' 'Also start a BFD session toward RemoteAddress')) + $peerSettings))
    Add-PodeOAComponentSchema -Name 'PeerUpdate' -Component (New-PodeOAObjectProperty -Description 'Only the fields you send are changed. A running session restarts.' -Properties $peerSettings)
    Add-PodeOAComponentSchema -Name 'RouteUpdate' -Component (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'Nlri' -Array -Description 'Prefixes to advertise (IPv4 or IPv6, not both in one call)')
            (New-PodeOAStringProperty -Name 'Withdrawn' -Array -Description 'Prefixes to withdraw')
            (& $str 'NextHop' 'Next hop; required for IPv6 over an IPv4 session')
            (New-PodeOAIntProperty -Name 'AsPath' -Array -Description 'AS_PATH (default: local AS)')))
    Add-PodeOAComponentSchema -Name 'Route' -Component (New-PodeOAObjectProperty -Properties @(
            (& $str 'Peer' 'Session name')
            (& $str 'Prefix' 'Prefix')
            (& $str 'NextHop' 'Next hop')
            (& $str 'AsPath' 'Space-separated AS_PATH')
            (& $str 'Origin' 'IGP, EGP or Incomplete')
            (& $int 'Med' 'MED (learned routes)')
            (& $int 'LocalPref' 'LOCAL_PREF (learned routes)')
            (& $str 'Community' 'Space-separated communities (learned routes)')
            (& $str 'Received' 'When the route was learned (learned routes)')))
    Add-PodeOAComponentSchema -Name 'Event' -Component (New-PodeOAObjectProperty -Properties @(
            (& $str 'Time' 'Timestamp')
            (& $str 'Peer' 'Session name')
            (& $str 'Direction' 'Sent or Received')
            (& $str 'Type' 'OPEN, UPDATE, NOTIFICATION or KEEPALIVE')
            (& $str 'Summary' 'Decoded summary')))
    $bfdSettings = @(
        (& $int 'Port' 'Remote BFD port (default 3784, or 4784 with MultiHop)')
        (& $int 'ListenPort' 'Local listen port')
        (& $str 'LocalAddress' 'Local source/bind address')
        (& $int 'TxMs' 'Desired min TX interval in ms')
        (& $int 'RxMs' 'Required min RX interval in ms'))
    Add-PodeOAComponentSchema -Name 'BfdSession' -Component (New-PodeOAObjectProperty -Properties @(
            (& $str 'Name' 'Session name')
            (& $str 'State' 'Local state')
            (& $str 'RemoteState' 'State the peer reports')
            (& $str 'Remote' 'Remote endpoint')
            (& $str 'LocalAddress' 'Local bind address, if set')
            (& $int 'RxMs' 'RX interval in ms')
            (& $int 'DetectMult' 'Detect multiplier')
            (& $int 'Sent' 'Packets sent')
            (& $int 'Received' 'Packets received')
            (& $bool 'Suppressed' 'Fault injection: silent')
            (& $str 'LastError' 'Last error, if any')))
    Add-PodeOAComponentSchema -Name 'BfdCreate' -Component (New-PodeOAObjectProperty -Properties (@(
                (& $str 'Name' 'Session name')
                (New-PodeOAStringProperty -Name 'RemoteAddress' -Required)
                (& $bool 'MultiHop' 'Use multihop BFD (RFC 5883, UDP 4784)')) + $bfdSettings))
    Add-PodeOAComponentSchema -Name 'BfdUpdate' -Component (New-PodeOAObjectProperty -Properties ($bfdSettings + (& $int 'DetectMult' 'Detect multiplier')))

    $nameParam = New-PodeOAStringProperty -Name 'name' -Description 'Session name' -Required | ConvertTo-PodeOAParameter -In Path
    $json = { param($schema) @{ 'application/json' = $schema } }
    $ref = { param($n, [switch]$Array) if ($Array) { New-PodeOASchemaProperty -Reference $n -Array } else { $n } }

    $doc = {
        param($method, $path, $summary, $tag, $id, $okCode, $okSchema, $body, [switch]$Name, $query)
        $r = Get-PodeRoute -Method $method -Path $path
        $r | Set-PodeOARouteInfo -Summary $summary -Tags $tag -OperationId $id -PassThru | Out-Null
        $params = @()
        if ($Name) { $params += $nameParam }
        if ($query) { $params += $query }
        if ($params.Count -or $body) {
            $a = @{ Route = $r; PassThru = $true }
            if ($params.Count) { $a.Parameters = $params }
            if ($body) { $a.RequestBody = New-PodeOARequestBody -Required -Content (& $json $body) }
            Set-PodeOARequest @a | Out-Null
        }
        $a = @{ Route = $r; StatusCode = $okCode; Description = $summary; PassThru = $true }
        if ($okSchema) { $a.Content = & $json $okSchema }
        Add-PodeOAResponse @a | Out-Null
        if ($method -ne 'Get' -or $path -match ':name') {
            Add-PodeOAResponse -Route $r -StatusCode 400 -Description 'Bad request' -Content (& $json 'Error') | Out-Null
        }
    }

    $dirQuery = New-PodeOAStringProperty -Name 'direction' -Enum 'Learned', 'Advertised' -Default 'Learned' -Description 'Routes from the peer, or the routes we advertise' | ConvertTo-PodeOAParameter -In Query

    & $doc Get '/api/bgp/peers' 'List BGP sessions' 'BGP' 'listBgpSessions' 200 (& $ref 'Peer' -Array)
    & $doc Post '/api/bgp/peers' 'Create a BGP session' 'BGP' 'createBgpSession' 201 'Peer' 'PeerCreate'
    & $doc Put '/api/bgp/peers/:name' 'Edit a BGP session' 'BGP' 'updateBgpSession' 200 'Peer' 'PeerUpdate' -Name
    & $doc Delete '/api/bgp/peers/:name' 'Remove a BGP session' 'BGP' 'removeBgpSession' 204 $null $null -Name
    & $doc Post '/api/bgp/peers/:name/stop' 'Stop a BGP session (Cease)' 'BGP' 'stopBgpSession' 202 $null $null -Name
    & $doc Post '/api/bgp/peers/:name/resume' 'Resume a stopped BGP session' 'BGP' 'resumeBgpSession' 200 'Peer' $null -Name
    & $doc Post '/api/bgp/peers/:name/update' 'Advertise or withdraw routes' 'BGP' 'sendBgpUpdate' 202 $null 'RouteUpdate' -Name
    & $doc Get '/api/bgp/peers/:name/routes' 'List learned or advertised routes' 'BGP' 'listBgpRoutes' 200 (& $ref 'Route' -Array) $null -Name -query $dirQuery
    & $doc Get '/api/bgp/events' 'Last 100 BGP messages' 'BGP' 'listBgpEvents' 200 (& $ref 'Event' -Array)
    & $doc Get '/api/bfd/sessions' 'List BFD sessions' 'BFD' 'listBfdSessions' 200 (& $ref 'BfdSession' -Array)
    & $doc Post '/api/bfd/sessions' 'Create a BFD session' 'BFD' 'createBfdSession' 201 'BfdSession' 'BfdCreate'
    & $doc Put '/api/bfd/sessions/:name' 'Edit a BFD session' 'BFD' 'updateBfdSession' 200 'BfdSession' 'BfdUpdate' -Name
    & $doc Delete '/api/bfd/sessions/:name' 'Remove a BFD session' 'BFD' 'removeBfdSession' 204 $null $null -Name
    & $doc Post '/api/bfd/sessions/:name/stop' 'Stop a BFD session' 'BFD' 'stopBfdSession' 202 $null $null -Name
    & $doc Post '/api/bfd/sessions/:name/resume' 'Resume a stopped BFD session' 'BFD' 'resumeBfdSession' 200 'BfdSession' $null -Name

    Use-PodeWebTemplates -Title 'PowerBGP' -Theme Dark -Logo '/icon.png' -FavIcon '/icon.png'

    Add-PodeWebPage -Name 'Peers' -Icon 'lan' -ScriptBlock {
        New-PodeWebCard -Name 'Start peer' -Content @(
            New-PodeWebForm -Name 'StartPeer' -ScriptBlock {
                $d = $WebEvent.Data
                try {
                    $p = @{ LocalAS = [uint32]$d.LocalAS; RouterId = [ipaddress]$d.RouterId; HoldTime = [uint16]$d.HoldTime; Port = [int]$d.Port }
                    if ($d.Name) { $p.Name = $d.Name }
                    if ($d.RemoteAddress) { $p.RemoteAddress = $d.RemoteAddress }
                    if ($d.RemoteAS) { $p.RemoteAS = [uint32]$d.RemoteAS }
                    if ($d.Mode -eq 'Passive (listen)') { $p.Passive = $true }
                    if ($d.AutoReconnect -eq 'No') { $p.AutoReconnect = $false }
                    if ($d.Password -and $IsLinux) { $p.Password = $d.Password }
                    $null = Start-BgpSession @p
                    if ($d.UseBFD -eq 'Yes' -and $d.RemoteAddress) {
                        $bn = "bfd-$(if ($d.Name) { $d.Name } else { $d.RemoteAddress })"
                        $null = Start-BfdSession -RemoteAddress $d.RemoteAddress -Name $bn
                    }
                    Show-PodeWebToast -Title 'PowerBGP' -Message 'Peer started'
                    Sync-PodeWebTable -Name 'PeerTable'
                }
                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
            } -Content @(
                New-PodeWebTextbox -Name 'Name' -Placeholder 'optional, e.g. nsx-t0'
                New-PodeWebSelect -Name 'Mode' -Options 'Active (connect)', 'Passive (listen)'
                New-PodeWebSelect -Name 'AutoReconnect' -Options 'Yes', 'No'
                New-PodeWebSelect -Name 'UseBFD' -Options 'No', 'Yes'
                New-PodeWebTextbox -Name 'RemoteAddress'
                New-PodeWebTextbox -Name 'RemoteAS' -Placeholder 'expected peer AS (optional)'
                New-PodeWebTextbox -Name 'Password' -Type Password -ReadOnly:(-not $IsLinux) -Placeholder $(if ($IsLinux) { 'TCP-MD5 (optional)' } else { 'TCP-MD5 needs Linux; disabled on Windows' })
                New-PodeWebTextbox -Name 'LocalAS' -Value '65001'
                New-PodeWebTextbox -Name 'RouterId' -Value '10.0.0.99'
                New-PodeWebTextbox -Name 'HoldTime' -Value '90'
                New-PodeWebTextbox -Name 'Port' -Value '179'
            )
        )
        if (@(Get-BgpSession).Count) {
        New-PodeWebCard -Name 'Edit peer (blank = unchanged; running peers restart)' -Content @(
            New-PodeWebForm -Name 'EditPeer' -ScriptBlock {
                $d = $WebEvent.Data
                try {
                    $p = @{ Name = $d.Peer }
                    if ($d.RemoteAS) { $p.RemoteAS = [uint32]$d.RemoteAS }
                    if ($d.LocalAS) { $p.LocalAS = [uint32]$d.LocalAS }
                    if ($d.RouterId) { $p.RouterId = [ipaddress]$d.RouterId }
                    if ($d.HoldTime) { $p.HoldTime = [uint16]$d.HoldTime }
                    if ($d.Port) { $p.Port = [int]$d.Port }
                    if ($d.AutoReconnect -in 'Yes', 'No') { $p.AutoReconnect = ($d.AutoReconnect -eq 'Yes') }
                    if ($d.Password -and $IsLinux) { $p.Password = $d.Password }
                    $null = Update-BgpSession @p
                    Show-PodeWebToast -Title 'PowerBGP' -Message 'Peer updated'
                    Sync-PodeWebTable -Name 'PeerTable'
                }
                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
            } -Content @(
                New-PodeWebSelect -Name 'Peer' -ScriptBlock { @(Get-BgpSession).Name }
                New-PodeWebTextbox -Name 'RemoteAS'
                New-PodeWebTextbox -Name 'LocalAS'
                New-PodeWebTextbox -Name 'RouterId'
                New-PodeWebTextbox -Name 'HoldTime'
                New-PodeWebTextbox -Name 'Port'
                New-PodeWebSelect -Name 'AutoReconnect' -Options 'Unchanged', 'Yes', 'No'
                New-PodeWebTextbox -Name 'Password' -Type Password -ReadOnly:(-not $IsLinux) -Placeholder $(if ($IsLinux) { 'TCP-MD5 (blank = unchanged)' } else { 'TCP-MD5 needs Linux; disabled on Windows' })
            )
        )
        }
        New-PodeWebTable -Name 'PeerTable' -DisplayName 'Peers' -DataColumn Name -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Name
            Initialize-PodeWebTableColumn -Key State
            Initialize-PodeWebTableColumn -Key Mode
            Initialize-PodeWebTableColumn -Key Remote
            Initialize-PodeWebTableColumn -Key PeerAS
            Initialize-PodeWebTableColumn -Key Uptime
            Initialize-PodeWebTableColumn -Key Sent
            Initialize-PodeWebTableColumn -Key Received
            Initialize-PodeWebTableColumn -Key Learned
            Initialize-PodeWebTableColumn -Key Advertised
            Initialize-PodeWebTableColumn -Key LastError
            Initialize-PodeWebTableColumn -Key Reconnects
            Initialize-PodeWebTableColumn -Key Action
        ) -ScriptBlock {
            Get-BgpSession | ForEach-Object {
                [ordered]@{
                    Name = $_.Name; State = $_.State; Mode = $_.Mode; Remote = $_.Remote; PeerAS = $_.PeerAS
                    Uptime = $_.Uptime; Sent = $_.Sent; Received = $_.Received; Learned = $_.Learned
                    Advertised = $_.Advertised; LastError = $_.LastError; Reconnects = $_.Reconnects
                    Action = @(
                        if ($_.State -eq 'Stopped') {
                            New-PodeWebButton -Name 'Resume' -Icon 'play' -DataValue $_.Name -ScriptBlock {
                                try { $null = Resume-BgpSession -Name $WebEvent.Data.Value -ErrorAction Stop }
                                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
                                Sync-PodeWebTable -Name 'PeerTable'
                            }
                        }
                        else {
                            New-PodeWebButton -Name 'Stop' -Icon 'stop' -DataValue $_.Name -ScriptBlock {
                                Stop-BgpSession -Name $WebEvent.Data.Value
                                Sync-PodeWebTable -Name 'PeerTable'
                            }
                        }
                        New-PodeWebButton -Name 'Remove' -Icon 'delete' -DataValue $_.Name -ScriptBlock {
                            Remove-BgpSession -Name $WebEvent.Data.Value -Confirm:$false
                            Sync-PodeWebTable -Name 'PeerTable'
                        }
                    )
                }
            }
        }
    }

    Add-PodeWebPage -Name 'Routes' -Icon 'routes' -ScriptBlock {
        New-PodeWebCard -Name 'Advertise / withdraw' -Content @(
            New-PodeWebForm -Name 'Advertise' -ScriptBlock {
                $d = $WebEvent.Data
                try {
                    $split = { param($s) @($s -split '[,\s]+' | Where-Object { $_ }) }
                    $p = @{ Name = $d.Peer }
                    if ($d.Action -eq 'Withdraw') { $p.Withdrawn = & $split $d.Prefixes }
                    else {
                        $p.Nlri = & $split $d.Prefixes
                        if ($d.NextHop) { $p.NextHop = [ipaddress]$d.NextHop }
                        if ($d.AsPath) { $p.AsPath = [uint32[]](& $split $d.AsPath) }
                        if ($d.Origin) { $p.Origin = $d.Origin }
                        if ($d.LocalPref) { $p.LocalPref = [uint32]$d.LocalPref }
                        if ($d.Med) { $p.Med = [uint32]$d.Med }
                        if ($d.Community) { $p.Community = & $split $d.Community }
                    }
                    Send-BgpUpdate @p
                    Show-PodeWebToast -Title 'PowerBGP' -Message "$($d.Action) sent"
                    Sync-PodeWebTable -Name 'Advertised'
                }
                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
            } -Content @(
                New-PodeWebSelect -Name 'Peer' -ScriptBlock { @(Get-BgpSession | Where-Object State -EQ 'Established').Name }
                New-PodeWebSelect -Name 'Action' -Options 'Advertise', 'Withdraw'
                New-PodeWebTextbox -Name 'Prefixes' -Placeholder 'e.g. 10.10.0.0/24, 10.10.1.0/24'
                New-PodeWebTextbox -Name 'NextHop' -Placeholder 'default: local address'
                New-PodeWebTextbox -Name 'AsPath' -Placeholder 'default: local AS'
                New-PodeWebSelect -Name 'Origin' -Options 'IGP', 'EGP', 'Incomplete'
                New-PodeWebTextbox -Name 'LocalPref'
                New-PodeWebTextbox -Name 'Med'
                New-PodeWebTextbox -Name 'Community' -Placeholder '65000:100'
            )
        )
        New-PodeWebTable -Name 'Advertised' -DisplayName 'Advertised routes' -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Peer
            Initialize-PodeWebTableColumn -Key Prefix
            Initialize-PodeWebTableColumn -Key NextHop
            Initialize-PodeWebTableColumn -Key AsPath
        ) -ScriptBlock {
            Get-BgpRoute -Direction Advertised | ForEach-Object { [ordered]@{ Peer = $_.Peer; Prefix = $_.Prefix; NextHop = "$($_.NextHop)"; AsPath = $_.AsPath } }
        }
        New-PodeWebTable -Name 'Learned' -DisplayName 'Learned routes' -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Peer
            Initialize-PodeWebTableColumn -Key Prefix
            Initialize-PodeWebTableColumn -Key NextHop
            Initialize-PodeWebTableColumn -Key AsPath
            Initialize-PodeWebTableColumn -Key Origin
            Initialize-PodeWebTableColumn -Key Med
            Initialize-PodeWebTableColumn -Key LocalPref
            Initialize-PodeWebTableColumn -Key Community
        ) -ScriptBlock {
            Get-BgpRoute -Direction Learned | ForEach-Object {
                [ordered]@{ Peer = $_.Peer; Prefix = $_.Prefix; NextHop = "$($_.NextHop)"; AsPath = $_.AsPath; Origin = $_.Origin; Med = $_.Med; LocalPref = $_.LocalPref; Community = $_.Community }
            }
        }
    }

    Add-PodeWebPage -Name 'Events' -Icon 'format-list-bulleted' -ScriptBlock {
        New-PodeWebForm -Name 'EventFilter' -SubmitText 'Apply' -ScriptBlock {
            $on = [bool]$WebEvent.Data['Show']
            [AppDomain]::CurrentDomain.SetData('PowerBGP.ShowKeepalives', $on)
            Sync-PodeWebTable -Name 'EventTable'
        } -Content @(
            New-PodeWebCheckbox -Name 'Show' -Options 'Keepalives' -AsSwitch
        )
        New-PodeWebTable -Name 'EventTable' -DisplayName 'Last 100 messages' -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Time
            Initialize-PodeWebTableColumn -Key Peer
            Initialize-PodeWebTableColumn -Key Direction
            Initialize-PodeWebTableColumn -Key Type
            Initialize-PodeWebTableColumn -Key Summary
        ) -ScriptBlock {
            $show = [bool][AppDomain]::CurrentDomain.GetData('PowerBGP.ShowKeepalives')
            Get-BgpEvent -Last 500 | Where-Object { $show -or $_.Type -ne 'KEEPALIVE' } | Sort-Object Time -Descending | Select-Object -First 100 | ForEach-Object {
                [ordered]@{ Time = $_.Time.ToString('HH:mm:ss.fff'); Peer = $_.Peer; Direction = $_.Direction; Type = $_.Type; Summary = $_.Summary }
            }
        }
    }

    Add-PodeWebPage -Name 'BFD' -Icon 'timer-outline' -ScriptBlock {
        New-PodeWebCard -Name 'Start BFD session' -Content @(
            New-PodeWebForm -Name 'StartBfd' -ScriptBlock {
                $d = $WebEvent.Data
                try {
                    $p = @{ RemoteAddress = $d.RemoteAddress; DesiredMinTxMs = [uint32]$d.TxMs; RequiredMinRxMs = [uint32]$d.RxMs; DetectMult = [int]$d.DetectMult }
                    if ($d.Port) { $p.Port = [int]$d.Port }
                    if ($d.ListenPort) { $p.ListenPort = [int]$d.ListenPort }
                    if ($d.LocalAddress) { $p.LocalAddress = [ipaddress]$d.LocalAddress }
                    if ($d.MultiHop -eq 'Yes') { $p.MultiHop = $true }
                    $null = Start-BfdSession @p
                    Show-PodeWebToast -Title 'PowerBGP' -Message 'BFD session started'
                    Sync-PodeWebTable -Name 'BfdTable'
                }
                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
            } -Content @(
                New-PodeWebSelect -Name 'RemoteAddress' -DisplayName 'BGP peer' -ScriptBlock {
                    @(Get-BgpSession | Where-Object RemoteAddress | ForEach-Object { $_.RemoteAddress } | Select-Object -Unique)
                }
                New-PodeWebSelect -Name 'MultiHop' -DisplayName 'Multihop (UDP 4784)' -Options 'No', 'Yes'
                New-PodeWebTextbox -Name 'LocalAddress' -DisplayName 'Local address (optional)'
                New-PodeWebTextbox -Name 'Port' -DisplayName 'Remote port (blank = 3784, or 4784 multihop)'
                New-PodeWebTextbox -Name 'ListenPort' -DisplayName 'Listen port (blank = same default)'
                New-PodeWebTextbox -Name 'TxMs' -Value '500'
                New-PodeWebTextbox -Name 'RxMs' -Value '500'
                New-PodeWebTextbox -Name 'DetectMult' -Value '3'
            )
        )
        if (@(Get-BfdSession).Count) {
            New-PodeWebCard -Name 'Edit BFD session (blank = unchanged; running sessions restart)' -Content @(
                New-PodeWebForm -Name 'EditBfd' -ScriptBlock {
                    $d = $WebEvent.Data
                    try {
                        $p = @{ Name = $d.Session }
                        if ($d.Port) { $p.Port = [int]$d.Port }
                        if ($d.ListenPort) { $p.ListenPort = [int]$d.ListenPort }
                        if ($d.LocalAddress) { $p.LocalAddress = [ipaddress]$d.LocalAddress }
                        if ($d.TxMs) { $p.DesiredMinTxMs = [uint32]$d.TxMs }
                        if ($d.RxMs) { $p.RequiredMinRxMs = [uint32]$d.RxMs }
                        if ($d.DetectMult) { $p.DetectMult = [int]$d.DetectMult }
                        $null = Update-BfdSession @p
                        Show-PodeWebToast -Title 'PowerBGP' -Message 'BFD session updated'
                        Sync-PodeWebTable -Name 'BfdTable'
                    }
                    catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
                } -Content @(
                    New-PodeWebSelect -Name 'Session' -ScriptBlock { @(Get-BfdSession).Name }
                    New-PodeWebTextbox -Name 'Port'
                    New-PodeWebTextbox -Name 'ListenPort'
                    New-PodeWebTextbox -Name 'LocalAddress'
                    New-PodeWebTextbox -Name 'TxMs'
                    New-PodeWebTextbox -Name 'RxMs'
                    New-PodeWebTextbox -Name 'DetectMult'
                )
            )
        }
        New-PodeWebTable -Name 'BfdTable' -DisplayName 'BFD sessions' -DataColumn Name -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Name
            Initialize-PodeWebTableColumn -Key State
            Initialize-PodeWebTableColumn -Key RemoteState
            Initialize-PodeWebTableColumn -Key Remote
            Initialize-PodeWebTableColumn -Key TxMs
            Initialize-PodeWebTableColumn -Key DetectMult
            Initialize-PodeWebTableColumn -Key Sent
            Initialize-PodeWebTableColumn -Key Received
            Initialize-PodeWebTableColumn -Key Suppressed
            Initialize-PodeWebTableColumn -Key Action
        ) -ScriptBlock {
            Get-BfdSession | ForEach-Object {
                [ordered]@{
                    Name = $_.Name; State = $_.State; RemoteState = $_.RemoteState; Remote = $_.Remote; TxMs = $_.TxMs
                    DetectMult = $_.DetectMult; Sent = $_.Sent; Received = $_.Received; Suppressed = $_.Suppressed
                    Action = @(
                        if ($_.State -eq 'Stopped') {
                            New-PodeWebButton -Name 'Resume' -Icon 'play' -DataValue $_.Name -ScriptBlock {
                                try { $null = Resume-BfdSession -Name $WebEvent.Data.Value -ErrorAction Stop }
                                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
                                Sync-PodeWebTable -Name 'BfdTable'
                            }
                        }
                        else {
                            New-PodeWebButton -Name 'Stop' -Icon 'stop' -DataValue $_.Name -ScriptBlock {
                                Stop-BfdSession -Name $WebEvent.Data.Value
                                Sync-PodeWebTable -Name 'BfdTable'
                            }
                        }
                        New-PodeWebButton -Name 'Remove' -Icon 'delete' -DataValue $_.Name -ScriptBlock {
                            Remove-BfdSession -Name $WebEvent.Data.Value -Confirm:$false
                            Sync-PodeWebTable -Name 'BfdTable'
                        }
                    )
                }
            }
        }
    }

    Add-PodeWebPage -Name 'Fault Injection' -Icon 'bug' -ScriptBlock {
        New-PodeWebCard -Name 'BGP keepalives' -Content @(
            New-PodeWebForm -Name 'Keepalives' -ScriptBlock {
                try {
                    Set-BgpSession -Name $WebEvent.Data.Peer -SuppressKeepalives ($WebEvent.Data.Keepalives -eq 'Suppressed')
                    Show-PodeWebToast -Title 'PowerBGP' -Message 'Updated'
                }
                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
            } -Content @(
                New-PodeWebSelect -Name 'Peer' -ScriptBlock { @(Get-BgpSession).Name }
                New-PodeWebSelect -Name 'Keepalives' -Options 'Enabled', 'Suppressed'
            )
        )
        New-PodeWebCard -Name 'BFD transmit' -Content @(
            New-PodeWebForm -Name 'BfdSuppress' -ScriptBlock {
                try {
                    Set-BfdSession -Name $WebEvent.Data.Session -Suppress ($WebEvent.Data.Transmit -eq 'Suppressed')
                    Show-PodeWebToast -Title 'PowerBGP' -Message 'Updated'
                }
                catch { Show-PodeWebToast -Title 'Error' -Message $_.Exception.Message -Icon 'alert' }
            } -Content @(
                New-PodeWebSelect -Name 'Session' -ScriptBlock { @(Get-BfdSession).Name }
                New-PodeWebSelect -Name 'Transmit' -Options 'Enabled', 'Suppressed'
            )
        )
    }

    Add-PodeWebPage -Name 'Packet Builder' -Icon 'hammer-wrench' -ScriptBlock {
        New-PodeWebCard -Name 'BGP / BFD message' -Content @(
            New-PodeWebForm -Name 'Build' -ScriptBlock {
                $d = $WebEvent.Data
                try {
                    $bytes = switch ($d.Type) {
                        'KEEPALIVE' { New-BgpKeepalive }
                        'OPEN' { New-BgpOpen -AS ([uint32]$d.AS) -RouterId ([ipaddress]$d.RouterId) -HoldTime ([uint16]$d.HoldTime) }
                        'NOTIFICATION (Cease)' { New-BgpNotification -Code 6 -Subcode 0 }
                        'BFD control (Down)' { New-BfdControl -State Down }
                        'UPDATE' {
                            $p = @{ Nlri = @($d.Prefixes -split '[,\s]+' | Where-Object { $_ }) }
                            if ($p.Nlri.Count) {
                                $p.NextHop = [ipaddress]$d.NextHop
                                $p.AsPath = @($d.AsPath -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [uint32]$_ })
                            }
                            New-BgpUpdate @p
                        }
                    }
                    New-PodeWebText -Value "$($bytes.Length) bytes" -Style Bold
                    New-PodeWebCodeBlock -Value (($bytes | Format-Packet) -join "`n") -NoHighlight
                }
                catch { New-PodeWebAlert -Type Error -Value $_.Exception.Message }
            } -Content @(
                New-PodeWebSelect -Name 'Type' -Options 'OPEN', 'UPDATE', 'KEEPALIVE', 'NOTIFICATION (Cease)', 'BFD control (Down)'
                New-PodeWebTextbox -Name 'AS' -Value '65001'
                New-PodeWebTextbox -Name 'RouterId' -Value '10.0.0.99'
                New-PodeWebTextbox -Name 'HoldTime' -Value '90'
                New-PodeWebTextbox -Name 'Prefixes' -Value '10.10.0.0/24'
                New-PodeWebTextbox -Name 'NextHop' -Value '192.168.1.99'
                New-PodeWebTextbox -Name 'AsPath' -Value '65001'
            )
        )
    }

    Set-PodeWebHomePage -Layouts @(
        New-PodeWebHero -Title 'PowerBGP' -Message 'BGP and BFD test peers, packet crafting and fault injection.'
        New-PodeWebTimer -Name 'HomeVisibility' -Interval 3 -ScriptBlock {
            if (@(Get-BgpSession).Count) { Show-PodeWebComponent -Id 'HomePeersCard' } else { Hide-PodeWebComponent -Id 'HomePeersCard' }
            if (@(Get-BfdSession).Count) { Show-PodeWebComponent -Id 'HomeBfdCard' } else { Hide-PodeWebComponent -Id 'HomeBfdCard' }
        }
        New-PodeWebCard -Name 'BGP peers' -Id 'HomePeersCard' -CssStyle @{ display = 'none' } -Content @(New-PodeWebTable -Name 'HomePeers' -DisplayName 'BGP peers' -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Name
            Initialize-PodeWebTableColumn -Key State
            Initialize-PodeWebTableColumn -Key Learned
        ) -ScriptBlock { Get-BgpSession | ForEach-Object { [ordered]@{ Name = $_.Name; State = $_.State; Learned = $_.Learned } } })
        New-PodeWebCard -Name 'BFD sessions' -Id 'HomeBfdCard' -CssStyle @{ display = 'none' } -Content @(New-PodeWebTable -Name 'HomeBfd' -DisplayName 'BFD sessions' -AutoRefresh -Columns @(
            Initialize-PodeWebTableColumn -Key Name
            Initialize-PodeWebTableColumn -Key State
        ) -ScriptBlock { Get-BfdSession | ForEach-Object { [ordered]@{ Name = $_.Name; State = $_.State } } })
    )
}
