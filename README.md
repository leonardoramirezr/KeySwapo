# KeySwapo

App nativa de macOS (Swift + AppKit/SwiftUI) que vive en la barra de menús y **cambia unas teclas por otras** según un JSON con el formato de [Karabiner-Elements](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/).

Está pensada para casos como este: que la tecla `|` escriba `_`, **sin tocar los demás caracteres de esa misma tecla**. Con la distribución Latinoamericana, ⇧ + `|` sigue escribiendo `°`.

## Qué hace con la configuración por defecto

La primera vez que se abre, KeySwapo crea `~/.config/keyswapo/keyswapo.json` con esta regla ([`examples/pipe-to-underscore.json`](examples/pipe-to-underscore.json)):

```json
{
    "description": "| sin shift -> _ , - + shift -> |",
    "manipulators": [
        {
            "from": {
                "key_code": "grave_accent_and_tilde",
                "modifiers": { "mandatory": [] }
            },
            "to": [{ "key_code": "slash", "modifiers": ["shift"] }],
            "type": "basic"
        },
        {
            "from": {
                "key_code": "slash",
                "modifiers": { "mandatory": ["shift"] }
            },
            "to": [{ "key_code": "grave_accent_and_tilde" }],
            "type": "basic"
        }
    ]
}
```

Con la distribución de teclado Latinoamericana, esto hace:

| Presionas | Sin KeySwapo | Con KeySwapo |
|-----------|:------------:|:------------:|
| `\|`      | `\|`         | **`_`**      |
| ⇧ + `\|`  | `°`          | `°` (igual)  |
| `-`       | `-`          | `-` (igual)  |
| ⇧ + `-`   | `_`          | **`\|`**     |

## Requisitos

- macOS 15 o posterior.
- Xcode Command Line Tools (`xcode-select --install`). No hace falta Xcode.

## Instalación

```sh
git clone https://github.com/leonardoramirezr/KeySwapo.git
cd KeySwapo
make install   # compila, copia la app a /Applications y la abre
```

Al abrirse por primera vez:

1. macOS pide el permiso de **Accesibilidad**, que es obligatorio para leer y cambiar teclas. Actívalo en *Ajustes del Sistema › Privacidad y seguridad › Accesibilidad*. No hace falta reiniciar la app: empieza a remapear en cuanto detecta el permiso.
2. Aparece el ícono ⌨ en la barra de menús y se abre la ventana de KeySwapo.

Para que arranque sola, activa *Abrir al iniciar sesión* en el menú o en la ventana.

> **Si recompilas la app**, la firma *ad hoc* cambia y macOS deja de reconocer el permiso anterior, aunque la app siga marcada en la lista. Quítala de la lista con «−» (o ejecuta `make reset-permissions`) y vuelve a concederlo. Para no repetir esto, firma siempre con un certificado estable, por ejemplo uno *Apple Development* (gratis con tu Apple ID en Xcode) o uno autofirmado de «Firma de código» creado con Acceso a Llaveros:
>
> ```sh
> SIGN_IDENTITY="Apple Development" make install
> ```

## Uso

**Menú de la barra** (⌨; se muestra ⚠︎ si falta el permiso o hay un error en el JSON):

- Estado actual y *Remapeo activado* para pausar o reanudar.
- Las reglas cargadas.
- *Configuración…*, *Recargar keyswapo.json*, *Mostrar keyswapo.json en Finder*, *Abrir al iniciar sesión* y *Salir*.

**Ventana de KeySwapo**, con tres pestañas:

- **Reglas**: cada cambio en palabras y con los caracteres reales de tu distribución de teclado, por ejemplo `«|» grave_accent_and_tilde → «_» shift + slash`. También muestra los errores y advertencias del JSON.
- **JSON**: editor del archivo de configuración. *Aplicar* (⌘S) valida el JSON y, si es correcto, lo guarda y lo aplica. *Importar archivo…* carga cualquier `.json`.
- **Probador de teclas**: escribe en el campo y verás el resultado real. La lista muestra la tecla física detectada (con el nombre que va en el JSON) y lo que KeySwapo envió en su lugar. Solo registra lo que escribes en esta ventana.

Si editas `~/.config/keyswapo/keyswapo.json` con otro editor, los cambios se aplican solos al guardar.

## Configuración

KeySwapo lee el mismo JSON que Karabiner-Elements. Acepta cualquiera de estas formas:

- Una regla: `{ "description": …, "manipulators": [ … ] }`, como el ejemplo de arriba.
- Un archivo de *complex modifications*: `{ "title": …, "rules": [ regla, … ] }`, como [`examples/advanced.json`](examples/advanced.json).
- Un arreglo de reglas: `[ regla, … ]`.
- Un `karabiner.json` completo: se usan las `complex_modifications.rules` del perfil seleccionado.
- Un solo manipulador: `{ "type": "basic", "from": …, "to": … }`.

También se permiten comentarios (`// …`) y comas finales.

### Campos soportados

| Campo | Significado |
|-------|-------------|
| `description` | Nombre de la regla (se muestra en el menú). |
| `enabled: false` | Desactiva la regla sin borrarla. |
| `type` | Debe ser `"basic"`. |
| `from.key_code` | Tecla física que se intercepta. |
| `from.modifiers.mandatory` | Modificadores que deben estar presionados. Se sueltan en la salida, salvo que `to` los vuelva a agregar. |
| `from.modifiers.optional` | Modificadores que además *pueden* estar presionados y se conservan en la salida. `["any"]` permite cualquiera. |
| `to` | Lista de teclas a enviar. Todas menos la última se envían como pulsación completa; la última queda presionada mientras mantengas la tecla original. `[]` desactiva la tecla. |
| `to[].key_code` | Tecla que se envía. |
| `to[].modifiers` | Modificadores con los que se envía (`"shift"` equivale a `"left_shift"`). |
| `to[].repeat` | `false` evita la autorrepetición al mantener la tecla. |

Si el JSON usa algo que KeySwapo no soporta (`to_if_alone`, `conditions`, `shell_command`, `simultaneous`, teclas modificadoras como `key_code`, …), se muestra un error con la ruta exacta, por ejemplo `manipulators[0].conditions`. **La configuración se aplica completa o no se aplica.** Si hay errores, siguen activas las últimas reglas válidas. Así nunca queda aplicada solo la mitad de un intercambio, como `|` → `_` sin la regla que devuelve `|`.

### Por qué `°` no se ve afectado

Se siguen las reglas de Karabiner-Elements:

- Un manipulador solo se aplica si están presionados **todos** sus modificadores `mandatory`…
- …y **ningún otro**, salvo los que aparezcan en `optional`.

`"modifiers": { "mandatory": [] }` sin `optional` significa «solo la tecla sola». Por eso ⇧ + `|` (y cualquier otra combinación con modificadores) no coincide con la regla y la tecla hace lo de siempre. Bloq Mayús también cuenta como modificador. Si quieres que la regla funcione con Bloq Mayús activado, agrega `"optional": ["caps_lock"]` (ver [`examples/advanced.json`](examples/advanced.json)).

Nombres de modificadores: `shift`, `control`, `option`, `command` (cualquiera de los dos lados), `left_shift`, `right_shift`, `left_control`, `right_control`, `left_option`, `right_option`, `left_command`, `right_command`, `fn`, `caps_lock` y `any` (solo en `optional`).

### Nombres de teclas

Son los de Karabiner-Elements y nombran la **posición física** de la tecla en un teclado estadounidense, no el carácter que escribe. Algunos ejemplos con la distribución Latinoamericana:

| Nombre | Tecla física | Escribe (Latinoamericano) |
|--------|--------------|---------------------------|
| `grave_accent_and_tilde` | a la izquierda del `1` | `\|` `°` |
| `slash` | a la izquierda del ⇧ derecho | `-` `_` |
| `hyphen` | a la derecha del `0` | `'` `?` |
| `non_us_backslash` | junto al ⇧ izquierdo (solo ISO) | `<` `>` |
| `spacebar`, `return_or_enter`, `tab`, `escape`, `delete_or_backspace` | | |
| `a` … `z`, `0` … `9`, `f1` … `f20`, `left_arrow`, `keypad_1`, … | | |

La forma más fácil de saber el nombre de una tecla es el **Probador de teclas**: presiónala y verás su nombre. La lista completa está en [`src/Core/KeyCodes.swift`](src/Core/KeyCodes.swift).

**Teclados ISO.** En los teclados ISO (con una tecla extra junto al ⇧ izquierdo), macOS intercambia internamente los códigos de la tecla a la izquierda del `1` y la de junto al ⇧ izquierdo. KeySwapo lo compensa según el teclado de cada pulsación. Así, `grave_accent_and_tilde` siempre es la tecla a la izquierda del `1`, igual que en Karabiner-Elements.

### Validar un JSON desde la terminal

```sh
make check CONFIG=examples/pipe-to-underscore.json
# o, con la app ya compilada:
/Applications/KeySwapo.app/Contents/MacOS/KeySwapo --check ruta/al/archivo.json
```

```text
✓ examples/pipe-to-underscore.json: 1 regla, 2 cambios de tecla
  Distribución: Latinoamericano · teclado ANSI

• | sin shift -> _ , - + shift -> |
  1. grave_accent_and_tilde «|»  →  shift + slash «_»
     Sin modificadores; con cualquier modificador la tecla no cambia
  2. shift + slash «_»  →  grave_accent_and_tilde «|»
     Con shift y ningún otro modificador
```

Sin archivo, valida `~/.config/keyswapo/keyswapo.json`. Si hay errores, los lista y termina con código 1. Para ver los caracteres de otra distribución de teclado, agrega `--layout com.apple.keylayout.LatinAmerican` (u otro ID; con uno que no existe, se listan los instalados).

## Cómo funciona

- KeySwapo instala un `CGEventTap` de sesión, que ve cada pulsación antes que las apps. Por eso necesita el permiso de Accesibilidad.
- Si una pulsación coincide con un manipulador, cambia en el propio evento el código de tecla y los modificadores (por ejemplo, `grave_accent_and_tilde` → `slash` con ⇧). La app que lo recibe traduce ese evento a un carácter con tu distribución de teclado, así que escribe `_`. El evento también lleva ese texto, para las apps que lo leen directamente. Las pulsaciones que no coinciden pasan intactas.
- Recuerda qué regla tomó cada tecla presionada. Así la autorrepetición y la liberación de la tecla se traducen igual, aunque sueltes ⇧ antes que la tecla o recargues las reglas en medio.
- Una salida nunca se vuelve a procesar, igual que en Karabiner. `|` → `_` no dispara la regla de ⇧ + `-` → `|`.

## Limitaciones

- En campos de contraseña, y en apps con *entrada de teclado segura* activada (como la Terminal), macOS no deja que ninguna app intercepte el teclado. Ahí no hay remapeo, y KeySwapo lo avisa en su ventana.
- No remapea teclas modificadoras (`caps_lock` → `escape`, etc.) ni usa `to_if_alone`, `conditions`, `shell_command` y otras funciones avanzadas de Karabiner. Para eso, usa Karabiner-Elements.
- No uses la misma regla en KeySwapo y en Karabiner-Elements a la vez: se aplicaría dos veces y los intercambios se desharían.

## Desarrollo

La estructura sigue [mac-app-template](https://github.com/leonardoramirezr/mac-app-template): Swift compilado con `swiftc`, un `Makefile` y `build.sh`, sin proyecto de Xcode.

```
.
├── src/
│   ├── Core/          # Lógica sin dependencias de plataforma: nombres de teclas,
│   │                  # modificadores, lector del JSON y remapeador (con pruebas)
│   └── App/           # macOS: event tap, barra de menús, ventana SwiftUI, --check
├── tests/
│   ├── main.swift     # Pruebas de src/Core
│   ├── layout/        # Nombres de teclas contra la distribución Latinoamericana real
│   └── e2e/           # Prueba de punta a punta del event tap (solo en CI)
├── examples/          # Configuraciones de ejemplo
├── Info.plist
├── build.sh
└── Makefile
```

| Comando | Qué hace |
|---------|----------|
| `make build` | Compila `build/KeySwapo.app` (firma *ad hoc*, o `SIGN_IDENTITY`). |
| `make test` | Ejecuta las pruebas de `src/Core` y comprueba, con la distribución Latinoamericana real de macOS, que los nombres de teclas escriben lo esperado (ANSI e ISO). |
| `make e2e-test` | Prueba de punta a punta: con la distribución Latinoamericana y el event tap de KeySwapo activo, simula `\|`, ⇧ + `\|`, `-` y ⇧ + `-` (teclados ANSI e ISO) y control + h → ←, y comprueba lo que recibe un campo de texto. Cambia la distribución de teclado y escribe en la sesión, así que solo corre en CI. |
| `make run` | Compila y abre la app desde `build/`. |
| `make install` | Compila, reemplaza `/Applications/KeySwapo.app` y la abre. |
| `make check CONFIG=…` | Valida un JSON y muestra lo que hace. |
| `make reset-permissions` | Olvida el permiso de Accesibilidad de KeySwapo. |
| `make clean` | Borra `build/`. |

En cada *push*, GitHub Actions ejecuta todas las pruebas y compila la app en macOS 15 y macOS 26. La app compilada queda como *artifact* del flujo. Al descargarla, macOS la bloquea por no estar notarizada; compilarla tú con `make install` evita ese paso.

## Licencia

[GNU General Public License v3.0](LICENSE).
