# Misc aliases
alias ghss='gh stack sync --remote origin'
alias cc='claude'
alias ccy='claude --dangerously-skip-permissions'
alias cca='claude --permission-mode auto'

# eza (ls replacement)
if command -v eza &>/dev/null; then
  alias ls='eza'
  alias ll='eza -l'
  alias la='eza -la'
  alias lt='eza --tree'
fi
