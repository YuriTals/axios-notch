<div align="center">
    <img src="docs/app-icon.png" width=200 height=200>
    <h1>Axios Notch</h1>
    <a href="README.md">English</a> · <b>Português (Brasil)</b>
</div>

<p align="center">
  O Axios Notch transforma o notch do MacBook num painel para os seus agentes de código.<br>
  Mostra quanto do plano de <b>Claude</b> e <b>Codex</b> você já usou, abre terminais sem tirar você<br>
  do que está fazendo e avisa quando uma resposta termina.
</p>

<p align="center">
  <img src="docs/screenshots/seletor.png" width="380" alt="Seletor Ferramentas ativas">
  <img src="docs/screenshots/uso.png" width="380" alt="Uso do plano do Claude">
</p>

<p align="center">
  <a href="https://github.com/YuriTals/axios-notch/releases/latest"><img src="https://img.shields.io/badge/download-latest-brightgreen?style=flat-square" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/requirements-macOS%2014%2B%20%C2%B7%20Apple%20Silicon-fa4e49?style=flat-square" alt="Requirements">
</p>

## Destaques

- **Ferramentas ativas:** Claude, Codex, Antigravity, até duas ferramentas suas e um Terminal, num clique.
- **Uso do plano:** % das janelas de 5 h e semanal de Claude e Codex, com previsão e avisos em 80 % e 90 %.
- **Terminais persistentes** dentro do notch: copie a última resposta e cole ou arraste imagens, arquivos e pastas.
- **Avisos:** resposta pronta e pedido de aprovação, com notificação opcional do macOS.
- **Vários monitores, temas, fontes Nerd Font incluídas**, português e inglês, e um visual Liquid Glass opcional (macOS 26+).

<p align="center">
  <img src="docs/screenshots/terminal.png" width="380" alt="Terminal dentro do notch">
  <img src="docs/screenshots/ajustes-experiencia.png" width="380" alt="Ajustes">
</p>

## Instalar

1. Baixe o `AxiosNotch-<versão>.dmg` da [página de Releases](https://github.com/YuriTals/axios-notch/releases/latest) e arraste o app para **Aplicativos**.
2. Abra o Axios Notch. Ele não tem ícone no Dock: vive no notch e num asterisco na barra de menus.

O app ainda não é notarizado pela Apple, então o macOS pode avisar na primeira abertura. Vá em **Ajustes do Sistema › Privacidade e Segurança** e clique em **Abrir Mesmo Assim**, ou rode:

```sh
xattr -dr com.apple.quarantine "/Applications/Axios Notch.app"
```

## Requisitos

- macOS 14 ou mais novo, em Mac com Apple Silicon. Macs Intel precisam compilar.
- As CLIs `claude`, `codex` e `agy` instaladas e com login feito, para usar cada ferramenta.

## Privacidade

Tudo acontece na sua máquina. Para mostrar o uso do plano, o app lê o login que as CLIs já guardam (Keychain do Claude Code e `~/.codex/auth.json`) e consulta só `api.anthropic.com` e `chatgpt.com`, a cada ~60 s. Ele **não grava, não registra e não renova** tokens. Esses dois endpoints não são documentados e podem mudar sem aviso. O botão de feedback abre o seu app de e-mail com versões e preferências, nunca tokens, conversas ou pastas.

## Compilar

```sh
swift run                   # modo desenvolvimento
scripts/build-app.sh        # gera "build/Axios Notch.app"
scripts/make-dmg.sh         # gera build/AxiosNotch-<versão>.dmg
swift test
```
