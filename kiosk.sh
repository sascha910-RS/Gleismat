#!/bin/bash
# Track-O-Mat – Kiosk-Starter für Raspberry Pi OS (X11 und Wayland/labwc)
#
#   kiosk.sh run     Chromium im Kiosk-Modus starten und bei Absturz/Beenden neu starten
#   kiosk.sh stop    Wartung: Neustart-Schleife anhalten und Chromium beenden
#   kiosk.sh start   Kiosk wieder aktivieren (aus der grafischen Sitzung heraus)
#   kiosk.sh status  Zustand anzeigen

APP_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
URL="file://$APP_DIR/track-o-mat.html"
PROFILE="$HOME/.config/track-o-mat-chromium"       # eigenes Profil, getrennt vom normalen Browser
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STOP_FLAG="$RUN_DIR/track-o-mat.stop"              # existiert = Wartungsmodus (verschwindet beim Reboot)
PID_FILE="$RUN_DIR/track-o-mat.pid"
WARM_FLAG="$RUN_DIR/track-o-mat.warm"              # existiert = seit dem Booten schon einmal gestartet
RESTART_DELAY=2
WARMUP_SEC=0                                       # einmaliger Neustart nach dem Booten (0 = aus, Pi 3: 30)

BROWSER="$(command -v chromium || command -v chromium-browser)"

loop_running() {
  [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

run_loop() {
  if loop_running; then echo "Track-O-Mat-Kiosk läuft bereits."; exit 0; fi
  if [ -z "$BROWSER" ]; then echo "Chromium nicht gefunden." >&2; exit 1; fi
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT
  rm -f "$STOP_FLAG"

  # Mehrere --disable-features überschreiben sich gegenseitig -> alles in EINER Liste
  FLAGS=(
    --kiosk                                   # Vollbild ohne Adressleiste, Tabs und Menüs
    --user-data-dir="$PROFILE"
    --no-first-run                            # kein Willkommens-Assistent
    --no-default-browser-check
    --noerrdialogs                            # keine Fehlerdialoge
    --disable-infobars
    --disable-session-crashed-bubble          # kein "Wiederherstellen"-Hinweis
    --hide-crash-restore-bubble
    --disable-features=Translate,TranslateUI,OverscrollHistoryNavigation,TouchpadOverscrollHistoryNavigation,MediaRouter,InfiniteSessionRestore
    --overscroll-history-navigation=0         # kein Zurück/Vorwärts per Wischen
    --disable-pinch                           # kein Pinch-Zoom
    --disable-pull-to-refresh-effect
    --check-for-update-interval=31536000      # keine Update-Meldungen (1 Jahr)
    --disable-component-update
    --disable-notifications
    --deny-permission-prompts
    --password-store=basic                    # keine Schlüsselbund-Abfrage
    --hide-scrollbars
    --force-device-scale-factor=1             # 1 CSS-Pixel = 1 Display-Pixel; die Seite skaliert sich selbst
    --window-position=0,0
    --disk-cache-size=10485760                # Cache auf 10 MB begrenzen (SD-Karte, RAM)
  )

  if [ -n "$WAYLAND_DISPLAY" ]; then
    FLAGS+=(--ozone-platform=wayland)
  else
    # X11: Bildschirmschoner und Energiesparen des Displays abschalten
    xset s off; xset s noblank; xset -dpms
  fi

  while [ ! -f "$STOP_FLAG" ]; do
    # Nach einem Absturz als "sauber beendet" markieren, damit kein Wiederherstellen-Dialog erscheint
    PREFS="$PROFILE/Default/Preferences"
    if [ -f "$PREFS" ]; then
      sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"[^"]*"/"exit_type":"Normal"/' "$PREFS"
    fi

    # Auf dem Pi 3 blieb das Chromium-Fenster beim ersten Start nach dem Booten leer;
    # erst der zweite Start zeigte die Seite. Mit WARMUP_SEC > 0 wird der erste Start
    # deshalb einmal beendet. Der Pi 4 braucht das nicht.
    if [ "$WARMUP_SEC" -gt 0 ] && [ ! -f "$WARM_FLAG" ]; then
      touch "$WARM_FLAG"
      (sleep "$WARMUP_SEC"; pkill -f -- "--user-data-dir=$PROFILE") &
    fi

    "$BROWSER" "${FLAGS[@]}" "$URL" >/dev/null 2>&1

    [ -f "$STOP_FLAG" ] && break
    sleep "$RESTART_DELAY"
  done
}

case "${1:-run}" in
  run)
    run_loop
    ;;
  stop)
    touch "$STOP_FLAG"
    pkill -f -- "--user-data-dir=$PROFILE"
    echo "Kiosk gestoppt (Wartungsmodus). Wieder aktivieren: Ctrl+Alt+Shift+K oder Neustart."
    ;;
  start)
    rm -f "$STOP_FLAG"
    if loop_running; then echo "Track-O-Mat-Kiosk läuft bereits."; exit 0; fi
    if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
      echo "Keine grafische Sitzung in dieser Konsole. Ctrl+Alt+Shift+K am Bildschirm drücken oder 'sudo reboot'." >&2
      exit 1
    fi
    nohup "$0" run >/dev/null 2>&1 &
    echo "Kiosk gestartet."
    ;;
  status)
    if loop_running; then echo "Kiosk läuft (PID $(cat "$PID_FILE"))."; else echo "Kiosk läuft nicht."; fi
    if [ -f "$STOP_FLAG" ]; then echo "Wartungsmodus aktiv."; fi
    ;;
  *)
    echo "Aufruf: $0 {run|stop|start|status}" >&2
    exit 2
    ;;
esac
