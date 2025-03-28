#!/bin/bash

# ./rls.sh 1 3200000 3000000 3500000 180 120 3150000 3750000 1200000
# Проверяем, переданы ли параметры
if [[ $# -ne 9 ]]; then
	echo "Использование: $0 <Номер_РЛС> <X_координата> <Y_координата> <Радиус действия> <Азимут> <Угол обзора> <СПРО_X_координата> <СПРО_Y_координата> <СПРО Радиус действия>"
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

RLS_NUM=$1
RLS_X=$2
RLS_Y=$3
RLS_RADIUS=$4
RLS_ALPHA=$5
RLS_ANGLE=$6

SPRO_X=$7
SPRO_Y=$8
SPRO_RADIUS=$9

# Каталоги
TARGETS_DIR="/tmp/GenTargets/Targets"

# Путь к файлу с обработанными целями
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROCESSED_FILES="$SCRIPT_DIR/temp/rls${RLS_NUM}_processed_files.txt"
>"$PROCESSED_FILES" # Очистка файла при запуске

# Определяем папку для сообщений и логов
MESSAGES_DIR="$SCRIPT_DIR/messages"
RLS_LOG="$SCRIPT_DIR/logs/rls${RLS_NUM}_log.txt"
>"$RLS_LOG" # Очистка файла при запуске

DETECTIONS_DIR="$MESSAGES_DIR/detections"
CHECK_DIR="$MESSAGES_DIR/check"
mkdir -p "$DETECTIONS_DIR"
mkdir -p "$CHECK_DIR"

# Количество файлов для анализа
MAX_FILES=50

# Ассоциативные массивы
declare -A TARGET_COORDS
declare -A TARGET_TYPE

# Генерация случайного имени файла (20 символов) - для сообщений
generate_random_filename() {
	cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1
}

encrypt_and_save_message() {
	local dir_path="$1"
	local content="$2"

	local filename="rls${RLS_NUM}$(generate_random_filename)"
	local file_path="${dir_path}${filename}"

	# Создаём контрольную сумму SHA-256
	local checksum=$(echo -n "$content" | sha256sum | cut -d' ' -f1)
	# Шифрование base64
	local encrypted_content=$(echo -n "$content" | base64)

	echo "$checksum $encrypted_content" >"$file_path"
}

# Проверка на существование
check_and_process_ping() {
	ping_file=$(find "$CHECK_DIR" -type f -name "ping_rls$RLS_NUM")

	if [[ -n "$ping_file" ]]; then
		rm -f "$ping_file"
		pong_file="$CHECK_DIR/pong_rls$RLS_NUM"
		touch "$pong_file"
	fi
}

# Функция вычисления расстояния (используем bc)
distance() {
	./math_modules/distance "$1" "$2" "$3" "$4"
}

# Функция вычисления попадания между лучами (используем bc)
beam() {
	./math_modules/beam "$1" "$2" "$RLS_X" "$RLS_Y" "$RLS_ALPHA" "$RLS_ANGLE"
}

check_trajectory_intersection() {
	./math_modules/check_trajectory_intersection "$1" "$2" "$3" "$4" "$SPRO_X" "$SPRO_Y" "$SPRO_RADIUS"
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

echo "РЛС${RLS_NUM} запущена!"

cleanup() {
	echo -e "\nРЛС$RLS_NUM остановлена!"
	exit 0
}

trap cleanup SIGINT SIGTERM

find "$MESSAGES_DIR" -type f -name "rls${RLS_NUM}*" -exec rm -f {} \;
while true; do
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

			x=$(grep -oP 'X:\s*\K\d+' "$target_file")
			y=$(grep -oP 'Y:\s*\K\d+' "$target_file")

			dist_to_target=$(distance "$RLS_X" "$RLS_Y" "$x" "$y")
			if (($(echo "$dist_to_target <= $RLS_RADIUS" | bc -l))); then
				target_in_angle=$(beam "$x" "$y" "$RLS_ALPHA" "$RLS_ANGLE")
				if [[ "$target_in_angle" -eq 1 ]]; then
					if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then
						if [[ -z "${TARGET_TYPE[$target_id]}" ]]; then
							prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
							prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

							speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
							target_type=$(get_target_type "$speed")
							TARGET_TYPE["$target_id"]="$target_type"

							if [[ $target_type == "ББ БР" ]]; then
								detection_time=$(date '+%d-%m %H:%M:%S.%3N')
								echo "$detection_time РЛС$RLS_NUM Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
								echo "$detection_time РЛС$RLS_NUM Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ${TARGET_TYPE[$target_id]}" >>"$RLS_LOG"
								if [[ $(check_trajectory_intersection "$prev_x" "$prev_y" "$x" "$y") -eq 1 ]]; then
									echo "$detection_time РЛС$RLS_NUM Цель ID:$target_id движется в сторону СПРО"
									encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time РЛС$RLS_NUM $target_id X:$x Y:$y $speed ББ БР-1" &
									echo "$detection_time РЛС$RLS_NUM Цель ID:$target_id движется в сторону СПРО" >>"$RLS_LOG"
								else
									encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time РЛС$RLS_NUM $target_id X:$x Y:$y $speed ББ БР" &
								fi
							fi
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
			unset TARGET_COORDS["$id"]
			unset TARGET_TYPE["$id"]
		fi
	done

	check_and_process_ping &
	total_lines=$(wc -l <"$RLS_LOG")
	if ((total_lines > 100)); then
		temp_file=$(mktemp) # Временный файл
		tail -n 100 "$RLS_LOG" >"$temp_file"
		mv "$temp_file" "$RLS_LOG"
	fi
done
