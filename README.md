# TaskOut

Lista de tareas para Mac pensada para TDAH: un panel angosto y flotante que se abre y se cierra con **⌥T** desde cualquier app. Las tareas se sincronizan con el Calendario de Apple (un calendario por categoría, con su color), así también las ves en tu iPhone.

> **¿Usas Windows?** Hay una versión aparte en [`windows/`](windows/README.md).

## Instalar

1. Descarga `TaskOut-x.y.z.zip` desde [Releases](../../releases/latest) y descomprímelo.
2. Arrastra **TaskOut.app** a `Aplicaciones`.
3. **Primera vez:** la app no está notarizada por Apple, así que macOS la bloquea. Haz **clic derecho sobre TaskOut → Abrir → Abrir**. Si no aparece la opción: *Ajustes del Sistema → Privacidad y seguridad → "Abrir de todos modos"*.
4. Acepta el permiso de Calendario cuando lo pida.

Las actualizaciones llegan solas dentro de la app (o desde el menú ✓ → *Buscar actualizaciones…*).

## Uso

| Tecla | Acción |
|---|---|
| `⌥T` | Mostrar / ocultar el panel |
| `Enter` | Crear tarea (campo con texto) / completar la seleccionada (campo vacío) |
| `↑` `↓` | Elegir tarea |
| mantener `⇥` | Ver la nota de la tarea sin salir de la lista |
| `⌘E` · `⌘→` · `⌘⌫` · `⌘Z` | Editar · pasar a mañana · borrar · deshacer |

## Privacidad

Todo es local. Las tareas se guardan en `~/Library/Application Support/TaskOut/data.json` y el único servicio que se usa es tu Calendario. La app no envía datos a ningún servidor; solo consulta este repositorio para ver si hay una versión nueva.

## Compilar desde el código

Requiere macOS 14+ y las herramientas de línea de comandos de Xcode.

```bash
./build.sh            # compila build/TaskOut.app
./build.sh install    # además la instala en /Applications
```

## Publicar una versión (mantenedor)

```bash
./release.sh 1.1.0 "Qué cambió"
```

Las actualizaciones se firman con una llave privada que vive solo en el Llavero del mantenedor (`SUPublicEDKey` en `Resources/Info.plist` es la pública).

## Licencia

MIT
