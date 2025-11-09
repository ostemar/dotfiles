# Nice git
Import-Module posh-git
oh-my-posh init pwsh --config  $PSScriptRoot/.oh-my-posh.ostemar.json | Invoke-Expression
Import-Module Terminal-Icons

# Help git with unicode characters
$env:LC_ALL='C.UTF-8'

# Colorize file listings
Import-Module Get-ChildItemColor
Set-Alias l Get-ChildItemColorFormatWide -Option AllScope

# sql alias
Set-Alias sql Invoke-SqlCmd

# ~ as home
function cuserprofile { Set-Location ~ }
Set-Alias ~ cuserprofile -Option AllScope

# Helper function to show Unicode character
function U
{
    param
    (
        [int] $Code
    )

    if ((0 -le $Code) -and ($Code -le 0xFFFF))
    {
        return [char] $Code
    }

    if ((0x10000 -le $Code) -and ($Code -le 0x10FFFF))
    {
        return [char]::ConvertFromUtf32($Code)
    }

    throw "Invalid character code $Code"
}
