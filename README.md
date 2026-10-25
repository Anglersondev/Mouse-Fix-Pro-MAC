# MouseFix Lite

Utilitário leve para macOS que deixa qualquer mouse tão bom quanto um trackpad: remapeia botões, adiciona gestos e deixa a rolagem suave. Inspirado no [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix), mas escrito do zero em Swift, sem dependências.

## Por que outro app

- **Funciona com mouses que "fingem ser teclado".** Muitos mouses Bluetooth (como o UGREEN vertical de 5 botões) mandam os botões laterais como tecla de mídia ou atalho de teclado, e não como Botão 4/5. Apps que só olham cliques de mouse não conseguem remapear esses botões. O MouseFix Lite lê o sinal cru do mouse (IOHID), descobre que veio do botão lateral, bloqueia a ação original e executa a que você escolheu: Mission Control, mesas, mídia, atalhos, abrir apps...
- **Leve.** Um único processo, sem helper em segundo plano, sem framework de atualização. O app fica parado até você usar o mouse: o tap de teclado só liga se algum botão do mouse chega como tecla, o de movimento só enquanto você segura um botão com gesto de arrastar, e o timer da rolagem suave só existe enquanto a página está rolando.
- **Perfis por app.** O mesmo botão pode fazer coisas diferentes no Safari, no Photoshop ou no VS Code.
- **Tela "O que o mouse envia".** Mostra em tempo real o que cada botão manda, para entender qualquer mouse.

## Recursos

| | |
|---|---|
| Botões | Clique, clique duplo, segurar, segurar e arrastar (↑ ↓ ← →) em qualquer botão extra |
| Ações | Mission Control, janelas do app, mostrar a mesa, Launchpad/Apps, trocar de mesa, voltar/avançar, clique do meio, mídia e volume, pesquisar palavra, captura de tela, bloquear tela, abas e zoom, atalho personalizado, abrir app |
| Rolagem | Suave com aceleração, direção invertida só no mouse, velocidade |
| Geral | Liga/desliga, abrir ao ligar o Mac, ícone na barra de menus opcional |

## Instalar

### Baixando pronto

1. Abra a aba **Actions** do repositório, entre no último build verde e baixe o artefato **MouseFixLite**.
2. Descompacte e arraste **MouseFix Lite.app** para Aplicativos.
3. Como o app não é assinado pela Apple, na primeira vez clique com o botão direito nele e escolha **Abrir**. Se o macOS ainda reclamar, rode `xattr -dr com.apple.quarantine "/Applications/MouseFix Lite.app"`.

### Compilando no seu Mac

Precisa das ferramentas de linha de comando do Xcode (`xcode-select --install`).

```bash
git clone https://github.com/Anglersondev/MouseFix-Lite-MAC.git
cd MouseFix-Lite-MAC
./scripts/build-app.sh --install
```

## Permissões

Na primeira vez o app mostra o que falta liberar em **Ajustes do Sistema › Privacidade e Segurança**:

- **Acessibilidade**: interceptar cliques e executar ações.
- **Monitoramento de Entrada**: ler o sinal cru de mouses que mandam botões como tecla.

Dica para quem compila várias vezes: a assinatura ad-hoc muda a cada build e o macOS esquece as permissões. Crie um certificado de assinatura de código no Acesso às Chaves (Assistente de Certificado › Criar um Certificado › Assinatura de Código) e compile com `SIGN_IDENTITY="Nome do certificado" ./scripts/build-app.sh --install`.

## Diagnóstico sem o app

`Tools/hidprobe.swift` mostra no Terminal o que cada botão do mouse envia (`swift Tools/hidprobe.swift`).

## Como funciona

```
Sources/MouseFixLite/
├── Core/
│   ├── MouseCore.swift      liga tudo; três event taps, cada um ativo só quando precisa
│   ├── HIDMonitor.swift     lê relatórios HID crus dos mouses numa thread própria
│   ├── ButtonEngine.swift   clique / duplo / segurar / arrastar, perfis por app
│   ├── ScrollEngine.swift   rolagem suave
│   ├── ActionRunner.swift   executa as ações (eventos sintéticos, Dock)
│   ├── EventTap.swift       invólucro de CGEventTap
│   └── Permissions.swift
├── Model/                   configuração (JSON em ~/Library/Application Support/MouseFixLite)
└── UI/                      SwiftUI
```

Quando o botão lateral chega como tecla, o `HIDMonitor` vê o relatório vindo do mouse e abre uma janela curta em que o evento de teclado/mídia/gesto que o macOS gera é engolido pelo event tap. Assim o atalho real do teclado continua funcionando normalmente.
