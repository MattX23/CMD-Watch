Output demo.gif

Set Shell "zsh"
Set FontSize 14
Set Width 680
Set Height 440
Set Theme "Catppuccin Mocha"
Set Padding 24
Set TypingSpeed 80ms
Set PlaybackSpeed 0.9

Hide
Type "PS1='➜  '"
Enter
Sleep 200ms
Type "source '/Users/mattnorthwood/Claude Playground/terminal-alias-suggester/demo_env.zsh'"
Enter
Sleep 300ms
Type "clear"
Enter
Sleep 300ms
Show

Sleep 700ms

# First miss — silent error
Type "push origin main"
Enter
Sleep 900ms

# Second miss — triggers the UI
Sleep 400ms
Type "push origin main"
Enter
Sleep 2800ms

# Pick suggestion [1]
Type "1"
Sleep 2500ms

# Show stats
Sleep 300ms
Type "cmdwatch stats"
Enter
Sleep 2200ms
