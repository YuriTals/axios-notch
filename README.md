# Axios Notch

App de menu bar para macOS que transforma o notch do MacBook num painel para os seus
agentes de código: acompanha o **uso de Claude Code e Codex** (% da janela de 5 h e da
semana), abre **terminais** sem sair do que você está fazendo e **avisa quando uma
resposta termina**.

- Fechado, o painel é do tamanho exato do notch. Ao passar o mouse ele cresce de leve e
  vibra no trackpad; ao clicar, abre o seletor **Ferramentas ativas** (Claude, Codex,
  Terminal).
- **Uso:** Claude e Codex mostram a porcentagem usada da janela de 5 h e da semana, com a
  hora em que reiniciam. Tokens e custo estimado aparecem como curiosidade.
- **Terminal:** shell limpo ou a CLI da ferramenta, com sessões que **continuam vivas** ao
  fechar o painel. Um ponto verde indica sessão ativa.
- **Avisos:** pontos pulando enquanto a resposta carrega; ao terminar, o notch desce com o
  ícone de quem respondeu e fica um contador vermelho de respostas não vistas.
- **Ajustes** (engrenagem no canto do seletor, ou "Ajustes…" no menu da barra): iniciar ao
  fazer login, reduzir movimento, vibração, duração do aviso e tamanho da fonte do terminal.

Requer macOS 14 ou superior.

## Instalar

1. Baixe `AxiosNotch-<versão>.dmg`, abra-o e **arraste o Axios Notch para Aplicativos**.
2. Abra o app. Ele não tem ícone no Dock: aparece no notch, e o menu da barra (asterisco) tem
   Ajustes, Pausar e Sair.

**Primeira abertura:** o app ainda não é notarizado pela Apple (isso exige uma conta de desenvolvedor
paga), então o macOS pode dizer que não conseguiu verificá-lo. Para abrir mesmo assim, vá em
**Ajustes do Sistema › Privacidade e Segurança**, role até a mensagem sobre o Axios Notch e clique em
**Abrir Mesmo Assim**. Também funciona, no Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/Axios Notch.app"
```

## Gerar o instalador

```bash
scripts/make-dmg.sh                  # build release + build/AxiosNotch-1.0.0.dmg
VERSION=1.2.0 scripts/make-dmg.sh    # outra versão
```

O script usa o [dmgbuild](https://github.com/dmgbuild/dmgbuild) e o Pillow num ambiente virtual
descartável em `build/.dmgvenv` (nada é instalado no sistema), monta a janela de instalação sem
depender do Finder e, no fim, abre o `.dmg` gerado para conferir que ele contém um app com assinatura
válida e o atalho para Aplicativos. O fundo da janela vem de `Packaging/dmg-background.png`
(`scripts/make-dmg-background.py` o redesenha). Para distribuir sem o aviso acima é preciso assinar
com um certificado Developer ID e notarizar: `CODESIGN_IDENTITY="Developer ID Application: …"`.

## Rodar

```bash
swift run                      # modo desenvolvimento
scripts/build-app.sh           # gera "build/Axios Notch.app" (assinado ad-hoc)
open "build/Axios Notch.app"
```

Para distribuir o `.app` para outros Macs é preciso assiná-lo com um certificado Developer ID
(`CODESIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh`) e notarizá-lo.
`scripts/make-icon.py` regenera o ícone a partir de `Axios Logo.png` (precisa do Pillow; o
resultado já está versionado em `Packaging/`).

Testes: `swift test`.

## O que o app lê e para onde envia

Tudo acontece na sua máquina, com o login que as CLIs já mantêm. O app **não grava nem
registra** tokens e **não os renova** (renovar giraria o refresh token da CLI).

| O quê | De onde | Para quê |
|---|---|---|
| Logs de sessão do Claude Code | `~/.claude/projects/**/*.jsonl` | tokens e custo estimado |
| Logs de sessão do Codex | `~/.codex/sessions/` | tokens e custo estimado |
| Token OAuth do Claude Code | Keychain (`Claude Code-credentials`) ou `~/.claude/.credentials.json` | consultar o uso do plano |
| Token do Codex | `~/.codex/auth.json` | consultar o uso do plano |

Conexões de saída (a cada ~60 s), só com o token da própria ferramenta:

- `https://api.anthropic.com/api/oauth/usage` — % usada das janelas de 5 h e semanal do Claude
- `https://chatgpt.com/backend-api/wham/usage` — o mesmo para o Codex

Esses dois endpoints **não têm documentação oficial** e podem mudar sem aviso. Se o token
expirar, o painel pede para abrir a CLI (que o renova) e volta sozinho.

## Como detecta "respondendo"

| Sessão | Sinal |
|---|---|
| Terminal limpo | há um comando em primeiro plano no terminal |
| Codex | o texto `esc to interrupt` está na tela (só aparece enquanto trabalha) |
| Claude | saída contínua depois do Enter; termina após 3 s de silêncio (heurística) |

## Estrutura

```
Sources/AxiosNotch/
  App/        ponto de entrada, menu da barra, carregamento de recursos
  Notch/      janela, forma, seletor, uso, ajustes, ícones
  Terminal/   sessões persistentes (SwiftTerm), detecção de resposta, fonte
  Agents/     leitores de logs, agregação, limites de uso (endpoints)
  Settings/   preferências e iniciar ao fazer login
Packaging/    Info.plist e ícone do .app
scripts/      build-app.sh, make-icon.py
```

## Fontes incluídas

O app leva dentro dele (em `Contents/Resources/Fonts`) as versões **Nerd Font Mono** de seis fontes de
terminal muito usadas, para que ninguém precise instalar nada: **JetBrains Mono**, **Fira Code**,
**Source Code Pro**, **Hack**, **Cascadia Code** e **IBM Plex Mono**. Elas só existem enquanto o app está
aberto (não são instaladas no Font Book). As variantes Nerd Font trazem os ícones usados por prompts como
Starship e Powerlevel10k. Menlo, Monaco e SF Mono são da Apple e já vêm no macOS.

As fontes originais são distribuídas sob a SIL Open Font License 1.1 (e Hack sob MIT); os textos das
licenças acompanham os arquivos em `Sources/AxiosNotch/Resources/Fonts/licenses/`. As versões
"patched" vêm do projeto [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts).

## Créditos

O desenho do notch (orelhas côncavas no topo, cantos inferiores arredondados e a animação de
mola) é inspirado no [Atoll](https://github.com/Ebullioscopic/Atoll), que é GPL v3. Este projeto
reimplementa o visual com código próprio e não copia código do Atoll.
