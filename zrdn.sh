#!/bin/bash

# ./zrdn.sh 1 9200000 4500000 2000000
# Проверяем, переданы ли параметры
if [[ $# -ne 4 ]]; then
	echo "Использование: $0 <Номер_ЗРДН> <X_координата> <Y_координата> <Радиус действия>"
	exit 1
fi

# Проверка на запуск от root
if [[ $EUID -eq 0 ]]; then
    echo "Ошибка: Запуск от root запрещен!"
    exit 1
fi

# Проверка ОС
if [[ "$(uname)" != "Linux" ]]; then
    echo "Ошибка: Скрипт поддерживается только в Linux!"
    exit 1
fi

# Проверка оболочки
if [[ -z "$BASH_VERSION" ]]; then
    echo "Ошибка: Скрипт должен выполняться в Bash!"
    exit 1
fi

ZRDN_NUM=$1
ZRDN_X=$2
ZRDN_Y=$3
ZRDN_RADIUS=$4

# Каталоги
TARGETS_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"

# Путь к файлу с обработанными целями
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROCESSED_FILES="$SCRIPT_DIR/temp/zrdn${ZRDN_NUM}_processed_files.txt"
>"$PROCESSED_FILES" # Очистка файла при запуске

# Определяем папку для сообщений и логов
MESSAGES_DIR="$SCRIPT_DIR/messages"
ZRDN_LOG="$SCRIPT_DIR/logs/zrdn${ZRDN_NUM}_log.txt"
>"$ZRDN_LOG" # Очистка файла при запуске

DETECTIONS_DIR="$MESSAGES_DIR/detections"
SHOOTING_DIR="$MESSAGES_DIR/shooting"
CHECK_DIR="$MESSAGES_DIR/check"
AMMO_DIR="$MESSAGES_DIR/ammo"
mkdir -p "$DETECTIONS_DIR"
mkdir -p "$SHOOTING_DIR"
mkdir -p "$CHECK_DIR"
mkdir -p "$AMMO_DIR"

# Боезапас и время пополнения
MISSILES=20
RELOAD_TIME=10     # Время до пополнения (в секундах)
LAST_RELOAD_TIME=0 # Временная метка последней перезарядки

# Количество файлов для анализа
MAX_FILES=50

# Ассоциативные массивы
declare -A TARGET_COORDS
declare -A TARGET_TYPE
declare -A TARGET_SHOT_TIME

# Генерация случайного имени файла (20 символов) - для сообщений
generate_random_filename() {
	cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1
}

encrypt_and_save_message() {
	local dir_path="$1"
	local content="$2"

	local filename="zrdn${ZRDN_NUM}$(generate_random_filename)"
	local file_path="${dir_path}${filename}"

	# Создаём контрольную сумму SHA-256
	local checksum=$(echo -n "$content" | sha256sum | cut -d' ' -f1)
	# Шифрование base64
	local encrypted_content=$(echo -n "$content" | base64)

	echo "$checksum $encrypted_content" >"$file_path"
}

# Проверка на существование
check_and_process_ping() {
	ping_file=$(find "$CHECK_DIR" -type f -name "ping_zrdn$ZRDN_NUM")

	if [[ -n "$ping_file" ]]; then
		rm -f "$ping_file"
		pong_file="$CHECK_DIR/pong_zrdn$ZRDN_NUM"
		touch "$pong_file"
	fi
}

# Функция вычисления расстояния (используем bc)
distance() {
	./distance "$1" "$2" "$3" "$4"
}

# Функция для определения типа цели по скорости
get_target_type() {
	local speed=$1
	if (($(echo "$speed >= 8000" | bc -l))); then
		echo "ББ БР"
	elif (($(echo "$speed >= 250" | bc -l))); then
		echo "Крылатая ракета"
	else
		echo "Самолет"
	fi
}

# Функция для декодирования ID цели из имени файла
decode_target_id() {
	local filename=$1
	local decoded_hex=""
	for ((i = 2; i <= ${#filename}; i += 4)); do
		decoded_hex+="${filename:$i:2}"
	done
	echo -n "$decoded_hex" | xxd -r -p
}

echo "ЗРДН${ZRDN_NUM} запущена!"

cleanup() {
	echo -e "\nЗРДН$ZRDN_NUM остановлена!"
	exit 0
}

trap cleanup SIGINT SIGTERM

find "$MESSAGES_DIR" -type f -name "zrdn${ZRDN_NUM}*" -exec rm -f {} \;
encrypt_and_save_message "$AMMO_DIR/" "$(date '+%d-%m %H:%M:%S.%3N') ЗРДН$ZRDN_NUM $MISSILES" &
while true; do
	current_time=$(date +%s)

	# Проверяем пополнение боезапаса
	if ((MISSILES == 0)) && ((current_time - LAST_RELOAD_TIME >= RELOAD_TIME)); then
		MISSILES=20
		LAST_RELOAD_TIME=$current_time
		ammo_time=$(date '+%d-%m %H:%M:%S.%3N')
		echo "$ammo_time ЗРДН$ZRDN_NUM Боезапас пополнен - $MISSILES снарядов!"
		encrypt_and_save_message "$AMMO_DIR/" "$ammo_time ЗРДН$ZRDN_NUM $MISSILES" &
		echo "$ammo_time ЗРДН$ZRDN_NUM Боезапас пополнен - $MISSILES снарядов!" >>"$ZRDN_LOG"
	fi

	unset FIRST_TARGET_FILE
	declare -A FIRST_TARGET_FILE
	found_second_file=false

	while ! $found_second_file; do
		# Получаем последние MAX_FILES файлов, отсортированные по времени
		mapfile -t latest_files < <(find "$TARGETS_DIR" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n "$MAX_FILES" | cut -d' ' -f2-)

		for target_file in "${latest_files[@]}"; do
			filename=$(basename "$target_file")

			if grep -qFx "$filename" "$PROCESSED_FILES"; then
				continue
			fi

			if [[ ${#filename} -le 2 ]]; then
				echo "$filename" >>"$PROCESSED_FILES"
				continue
			fi

			target_id=$(decode_target_id "$filename")

			# Если для этой цели уже был найден файл — завершаем поиск
			if [[ -n "${FIRST_TARGET_FILE[$target_id]}" ]]; then
				found_second_file=true
				break
			fi

			FIRST_TARGET_FILE["$target_id"]="$target_file"
			echo "$filename" >>"$PROCESSED_FILES"

			if [[ ("${TARGET_TYPE[$target_id]}" == "Крылатая ракета" || "${TARGET_TYPE[$target_id]}" == "Самолет") && -n "${TARGET_SHOT_TIME[$target_id]}" ]]; then
				echo "$(date '+%d-%m %H:%M:%S.%3N') Цель ID:$target_id промах ЗРДН$ZRDN_NUM при выстреле ${TARGET_SHOT_TIME[$target_id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$target_id]} ЗРДН$ZRDN_NUM $target_id 0" &
				echo "${TARGET_SHOT_TIME[$target_id]} ЗРДН$ZRDN_NUM Выстрел по цели ID:$target_id - промах!" >>"$ZRDN_LOG"
				unset TARGET_SHOT_TIME["$target_id"]
			fi

			x=$(grep -oP 'X:\s*\K\d+' "$target_file")
			y=$(grep -oP 'Y:\s*\K\d+' "$target_file")

			dist_to_target=$(distance "$ZRDN_X" "$ZRDN_Y" "$x" "$y")
			if (($(echo "$dist_to_target <= $ZRDN_RADIUS" | bc -l))); then
				if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then
					if [[ -z "${TARGET_TYPE[$target_id]}" ]]; then
						prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
						prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

						speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
						target_type=$(get_target_type "$speed")
						TARGET_TYPE["$target_id"]="$target_type"

						if [[ "${TARGET_TYPE[$target_id]}" == "Крылатая ракета" || "${TARGET_TYPE[$target_id]}" == "Самолет" ]]; then
							detection_time=$(date '+%d-%m %H:%M:%S.%3N')
							echo "$detection_time ЗРДН$ZRDN_NUM Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
							encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time ЗРДН$ZRDN_NUM $target_id $speed ${TARGET_TYPE[$target_id]}" &
							echo "$detection_time ЗРДН$ZRDN_NUM Обнаружена цель ID:$target_id скорость: $speed м/с ${TARGET_TYPE[$target_id]}" >>"$ZRDN_LOG"
						fi
					fi

					if [[ "${TARGET_TYPE[$target_id]}" == "Крылатая ракета" || "${TARGET_TYPE[$target_id]}" == "Самолет" ]]; then
						if ((MISSILES > 0)); then
							shot_time=$(date '+%d-%m %H:%M:%S.%3N')
							echo "$shot_time ЗРДН$ZRDN_NUM Атака цели ID:$target_id - Выстрел!"
							echo "ЗРДН$ZRDN_NUM" >"$DESTROY_DIR/$target_id"
							((MISSILES--))
							TARGET_SHOT_TIME["$target_id"]="$shot_time"

							if ((MISSILES == 0)); then
								LAST_RELOAD_TIME=$(date +%s)
								echo "$(date '+%d-%m %H:%M:%S.%3N') ЗРДН$ZRDN_NUM Боезапас исчерпан! Начинается перезарядка"
							fi
						else
							echo "$(date '+%d-%m %H:%M:%S.%3N') ЗРДН$ZRDN_NUM Невозможно атаковать цель ID:$target_id - Боезапас исчерпан!"
						fi
					fi
				fi
				TARGET_COORDS["$target_id"]="$x,$y"
			fi
		done

		if ! $found_second_file; then
			sleep 0.01
		fi
	done

	for id in "${!TARGET_COORDS[@]}"; do
		if [[ -z "${FIRST_TARGET_FILE[$id]}" ]]; then
			if [[ ("${TARGET_TYPE[$id]}" == "Крылатая ракета" || "${TARGET_TYPE[$id]}" == "Самолет") && -n "${TARGET_SHOT_TIME[$id]}" ]]; then
				echo "$(date '+%d-%m %H:%M:%S.%3N') Цель ID:$id уничтожена ЗРДН$ZRDN_NUM при выстреле ${TARGET_SHOT_TIME[$id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$id]} ЗРДН$ZRDN_NUM $id 1" &
				echo "${TARGET_SHOT_TIME[$id]} ЗРДН$ZRDN_NUM Выстрел по цели ID:$id - уничтожена!" >>"$ZRDN_LOG"
			fi
			unset TARGET_COORDS["$id"]
			unset TARGET_TYPE["$id"]
			unset TARGET_SHOT_TIME["$id"]
		fi
	done

	check_and_process_ping &
	total_lines=$(wc -l <"$ZRDN_LOG")
	if ((total_lines > 100)); then
		temp_file=$(mktemp) # Временный файл
		tail -n 100 "$ZRDN_LOG" >"$temp_file"
		mv "$temp_file" "$ZRDN_LOG"
	fi
done
