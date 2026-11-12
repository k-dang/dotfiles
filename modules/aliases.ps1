# Misc aliases
function cc
{ 
    claude 
}

function ccy
{
    claude --dangerously-skip-permissions
}

function cca
{
    claude --enable-auto-mode
}

# eza (ls replacement)
#
# Only ll and lt, unlike the zsh side which also defines ls and la. The coreutils
# block in the PowerShell profile rewrites typed `ls`/`la` to coreutils ls.cmd
# before they resolve, so eza versions of those two would never run.
if (Get-Command eza -ErrorAction SilentlyContinue)
{
    function ll
    {
        eza -l @args
    }

    function lt
    {
        eza --tree @args
    }
}
