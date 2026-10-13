# TaskOut para Windows

Misma app que la de Mac, hecha con Electron: panel angosto y flotante que se abre y cierra con **Alt+T** desde cualquier app. Las tareas se sincronizan con tu Calendario de Microsoft (Outlook.com / Microsoft 365): un calendario por categoría, con su color. La app **Calendario de Windows** y el móvil muestran esos mismos calendarios.

La versión de Mac vive en `Sources/` y no comparte código con esta; cada una se versiona y se publica por separado.

## Teclas

| Tecla | Acción |
|---|---|
| `Alt+T` | Mostrar / ocultar el panel |
| `Enter` | Crear tarea (campo con texto) / completar la seleccionada (campo vacío) |
| `↑` `↓` | Elegir tarea |
| mantener `Tab` | Ver la nota de la tarea |
| `Ctrl+E` · `Ctrl+→` · `Ctrl+⌫` · `Ctrl+Z` | Editar · pasar a mañana · borrar · deshacer |

## Conectar el Calendario (una sola vez, para quien publica la app)

Microsoft exige que toda app que lea calendarios tenga un "ID de aplicación". Es gratis y no es secreto:

1. Entra a <https://entra.microsoft.com> → **Identidad › Aplicaciones › Registros de aplicaciones › Nuevo registro**.
2. Nombre: `TaskOut`. Tipos de cuenta: **Cuentas en cualquier directorio organizativo y cuentas personales de Microsoft**.
3. URI de redirección: plataforma **Cliente público/nativo (móvil y escritorio)**, valor `http://localhost`.
4. Registrar. En **Autenticación**, activa **Permitir flujos de cliente público** = Sí.
5. En **Permisos de API** deben estar (delegados): `User.Read` y `Calendars.ReadWrite`.
6. Copia el **Id. de aplicación (cliente)** a `windows/config.json` → `microsoftClientId`, haz commit y publica.

Los usuarios solo hacen clic en el ícono del calendario (arriba a la derecha) y aceptan el permiso en el navegador. Sin ese ID la app funciona igual como lista de tareas, pero sin calendario.

Los calendarios de Graph solo admiten colores "con nombre", así que cada categoría usa el más parecido a su color (el morado cae en azul o rosa).

## Instalar (usuarios)

Descarga **TaskOut-Setup.exe** desde el release [TaskOut para Windows](../../releases/tag/windows-latest) y ejecútalo. Como no está firmado, Windows SmartScreen mostrará un aviso: **Más información → Ejecutar de todas formas**. Se actualiza solo.

Datos locales en `%APPDATA%\TaskOut\data.json`. El token del calendario se guarda cifrado con Windows (DPAPI).

## Desarrollo

```bash
cd windows
npm install
npm start          # corre la app (en Mac también sirve para probar la interfaz)
npm run dist       # instalador en windows/dist (hay que correrlo en Windows)
```

## Publicar una versión

```bash
./windows/release.sh 1.1.0
```

Sube un tag `win-v1.1.0`; GitHub Actions compila en Windows y reemplaza los archivos del release `windows-latest`, que es de donde las apps instaladas se actualizan. Es un release *prerelease* a propósito: la actualización de Mac usa `releases/latest`, y un release de Windows marcado como "latest" la rompería.
