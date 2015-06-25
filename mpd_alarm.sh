#!/bin/bash
if date -f ~/.vocations +%F | grep `date +%F`
then
    exit 0
fi

export MPD_HOST="127.0.0.1"

# сохраняем состояние mpd в env, соответствующих названиям статусов
export `mpc status | sed -n '$ { s#: #=#g; s#%##; s#[[:blank:]]\+#\n#g; p } '`

# добавляем 3 рандомных альбома
mpc list album | shuf | head -3 | xargs -i -d '\n' mpc findadd Album {}

# выключить одиночный режим
mpc -q single off
mpc -q volume 10
mpc -q play

# функция восстановления состоянияи завершения скрипта
function stopScript {
    mpc -q pause
    mpc -q volume $volume
    mpc -q single $single
    kill $(jobs -p) 2>/dev/null
    kill $$
}
export -f stopScript
trap 'stopScript' EXIT SIGINT

# нарастание громкости
while true; do sleep 5; mpc -q volume +1; done &
# выключение на паузе
while true; do mpc -q idle player > /dev/null; [[ -z `mpc status | sed -n '2 { /playing/p }'` ]] && stopScript; done &

# выключение по таймауту
sleep 400
stopScript
