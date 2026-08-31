# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Theme handled by Starship.
ZSH_THEME=""

# Which plugins would you like to load?
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

ZSH_AUTOSUGGEST_STRATEGY=(history completion)

source "$ZSH/oh-my-zsh.sh"


# ------------------------------------------------------------------------------
# User configuration
# ------------------------------------------------------------------------------

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi


# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------

alias ls="lsd -lag"
alias cex="python3 ~/.scripts/cex.py"
alias cleanup="$HOME/.local/bin/cleanup.py"
alias plmedit="QT_QPA_PLATFORMTHEME=kde kcmshell6 kcm_plasmalogin"


# ------------------------------------------------------------------------------
# Dotfiles Git repository
# ------------------------------------------------------------------------------

# Bare Git repository:
#
#   Git dir:   ~/.mis-dotfiles
#   Work tree: ~/
#
# Usage:
#
#   dotfiles status
#   dotfiles diff
#   dotfiles add ~/.zshrc
#   dotfiles add .config/quickshell
#   dotfiles add .
#   dotfiles commit -m "Update Quickshell"
#   dotfiles push
#
# `dotfiles add .` is treated specially:
# instead of scanning the entire $HOME directory, it detects the configuration
# roots that are already managed by the repository and runs `git add -A`
# only on those paths.
#
# This stages new, modified and deleted files inside already-managed configs
# without recursively scanning the complete home directory.
#
# To start tracking a completely new config, add it explicitly once:
#
#   dotfiles add .config/alacritty
#
# Once committed, future `dotfiles add .` calls will detect it automatically.

function dotfiles() {
    local git_dir="$HOME/.mis-dotfiles"
    local work_tree="$HOME"

    # Special case: "dotfiles add ."
    #
    # Instead of scanning the whole $HOME directory, determine which
    # configuration roots already belong to the repository and update
    # only those.
    if [[ "$1" == "add" && "$2" == "." && $# -eq 2 ]]; then
        local -a managed_roots

        managed_roots=("${(@f)$(
            command /usr/bin/git \
                --git-dir="$git_dir" \
                --work-tree="$work_tree" \
                ls-files |
            awk -F/ '
                # ~/.config/foo/... -> .config/foo
                $1 == ".config" && NF >= 2 {
                    print $1 "/" $2
                    next
                }

                # ~/.local/foo/... -> .local/foo
                #
                # This avoids scanning the whole ~/.local directory if,
                # for example, ~/.local/bin is tracked in the future.
                $1 == ".local" && NF >= 2 {
                    print $1 "/" $2
                    next
                }

                # Other HOME directories:
                # .scripts/foo -> .scripts
                # .github/foo  -> .github
                NF >= 2 {
                    print $1
                    next
                }

                # Files directly inside HOME:
                # .zshrc
                # .gitignore
                {
                    print $1
                }
            ' |
            sort -u
        )}")

        if (( ${#managed_roots[@]} == 0 )); then
            echo "No hay rutas gestionadas por el repositorio."
            return 0
        fi

        command /usr/bin/git \
            --git-dir="$git_dir" \
            --work-tree="$work_tree" \
            add -A -- "${managed_roots[@]}"

        return $?
    fi

    # Every other command behaves like normal Git.
    command /usr/bin/git \
        --git-dir="$git_dir" \
        --work-tree="$work_tree" \
        "$@"
}

# Give the dotfiles wrapper Git's normal Zsh completion.
compdef dotfiles=git


# ------------------------------------------------------------------------------
# Theme / wallpaper helper
# ------------------------------------------------------------------------------

function theme() {
    awww img "$1" --transition-type wipe
    wal -i "$1" -n

    # Refresh Kitty instantly to apply the new background.
    pkill -SIGUSR1 kitty 2>/dev/null
}


# ------------------------------------------------------------------------------
# Prompt
# ------------------------------------------------------------------------------

eval "$(starship init zsh)"


# ------------------------------------------------------------------------------
# Startup
# ------------------------------------------------------------------------------

clear
echo ' '
fastfetch -l arch
echo ' '


# ------------------------------------------------------------------------------
# PATH
# ------------------------------------------------------------------------------

export PATH="$HOME/.local/bin:$PATH"
