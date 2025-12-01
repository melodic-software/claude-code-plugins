# Shell Customization

## Oh My Posh

- [https://ohmyposh.dev/](https://ohmyposh.dev/)
- [https://ohmyposh.dev/docs/installation/windows](https://ohmyposh.dev/docs/installation/windows)
- [https://learn.microsoft.com/en-us/windows/terminal/tutorials/custom-prompt-setup](https://learn.microsoft.com/en-us/windows/terminal/tutorials/custom-prompt-setup)

```powershell
winget install --id JanDeDobbeleer.OhMyPosh -e --source winget
```

### Fonts

In order for symbols to appear properly, you will need to install fonts. The official recommendation is the Meslo Nerd Font (Meslo LGM NF), but you can choose whichever you want.

[https://ohmyposh.dev/docs/installation/fonts](https://ohmyposh.dev/docs/installation/fonts)

The easiest method is to use the built in font installation:

```powershell
oh-my-posh font install # select a font
oh-my-posh font install meslo # install meslo font
```

Make sure to configure your terminal to use the font you have installed. The following sections will show you how to do this for the most popular terminals.

For Windows terminal follow this guide: [https://ohmyposh.dev/docs/installation/fonts#configuration](https://ohmyposh.dev/docs/installation/fonts#configuration)

#### Configure Terminal

You'll also want to configure your PowerShell profile to use Oh My Posh: [https://ohmyposh.dev/docs/installation/prompt?shell=powershell](https://ohmyposh.dev/docs/installation/prompt?shell=powershell)
