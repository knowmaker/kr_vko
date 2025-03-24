#!/bin/bash

SCRIPT_DIR=$(dirname "$(realpath "$0")")
DB_DIR="$SCRIPT_DIR/db"
DB_FILE="$DB_DIR/vko.db"
MESSAGES_DIR="$SCRIPT_DIR/messages"
DETECTIONS_DIR="$MESSAGES_DIR/detections"
SHOOTING_DIR="$MESSAGES_DIR/shooting"
AMMO_DIR="$MESSAGES_DIR/ammo"
CHECK_DIR="$MESSAGES_DIR/check"

# Определяем папку для логов
KP_LOG="$SCRIPT_DIR/logs/kp_log.txt"
>"$KP_LOG" # Очистка файла при запуске

# Создание базы данных и таблиц, если они не существуют
initialize_database() {
	if [[ -f "$DB_FILE" ]]; then
		echo "База данных существует, удаляем"
		rm -f "$DB_FILE"
	fi

	sqlite3 "$DB_FILE" <<EOF
    CREATE TABLE IF NOT EXISTS targets (
        id TEXT PRIMARY KEY,
        speed REAL,
        ttype TEXT,
        direction BOOLEAN
    );

    CREATE TABLE IF NOT EXISTS systems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE
    );

	CREATE TABLE IF NOT EXISTS ammo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        system_id INTEGER,
		count INTEGER,
        timestamp TEXT,
		FOREIGN KEY (system_id) REFERENCES systems (id)
    );

    CREATE TABLE IF NOT EXISTS detections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_id TEXT,
        system_id INTEGER,
        timestamp TEXT,
        FOREIGN KEY (target_id) REFERENCES targets (id),
        FOREIGN KEY (system_id) REFERENCES systems (id)
    );

    CREATE TABLE IF NOT EXISTS shooting (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_id TEXT,
        system_id INTEGER,
        result BOOLEAN,
        timestamp TEXT,
        FOREIGN KEY (target_id) REFERENCES targets (id),
        FOREIGN KEY (system_id) REFERENCES systems (id)
    );
EOF
}

# Функция для расшифровки и проверки файла
decrypt_and_verify_message() {
	local file_path="$1"
	local file_content=$(<"$file_path")

	# Извлекаем контрольную сумму и зашифрованный текст
	local saved_checksum=$(echo "$file_content" | head -n1 | cut -d' ' -f1)
	local encrypted_content=$(echo "$file_content" | cut -d' ' -f2-)

	# Декодируем обратно в текст
	local decrypted_content=$(echo -n "$encrypted_content" | base64 -d)

	# Вычисляем хеш и сверяем
	local calculated_checksum=$(echo -n "$decrypted_content" | sha256sum | cut -d' ' -f1)

	if [ "$saved_checksum" = "$calculated_checksum" ]; then
		echo "$decrypted_content"
	else
		echo "ВНИМАНИЕ!ВНИМАНИЕ!ВНИМАНИЕ! ДАННЫЕ ПОВРЕЖДЕНЫ! ВОЗМОЖЕН НСД!" >&2
		return 1
	fi
}

# Функция для получения ID системы (добавляет в базу, если ее нет)
get_system_id() {
	local system_name="$1"
	local system_num

	system_num=$(sqlite3 "$DB_FILE" "SELECT id FROM systems WHERE name='$system_name';")

	if [[ -z "$system_num" ]]; then
		sqlite3 "$DB_FILE" "INSERT INTO systems (name) VALUES ('$system_name');"
		system_num=$(sqlite3 "$DB_FILE" "SELECT id FROM systems WHERE name='$system_name';")
	fi

	echo "$system_num"
}

# Функция обработки файла обнаружений
process_detection() {
	local decrypted_content="$1"
	local file="$2"

	timestamp=$(echo "$decrypted_content" | cut -d' ' -f1,2)
	system_id=$(echo "$decrypted_content" | cut -d' ' -f3)
	target_id=$(echo "$decrypted_content" | cut -d' ' -f4)
	speed=$(echo "$decrypted_content" | cut -d' ' -f5)
	target_type=$(echo "$decrypted_content" | cut -d' ' -f6-)

	echo "$timestamp $system_id $target_id $speed $target_type"

	if [[ "$target_type" == "ББ БР-1" ]]; then
		direction=1
		target_type="ББ БР"
		echo "$timestamp $system_id Обнаружена цель ID:$target_id скорость: $speed м/с $target_type" >>"$KP_LOG"
		echo "$timestamp $system_id Цель ID:$target_id движется в сторону СПРО" >>"$KP_LOG"
	else
		direction="NULL"
		echo "$timestamp $system_id Обнаружена цель ID:$target_id скорость: $speed м/с $target_type" >>"$KP_LOG"
	fi

	sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO targets (id, speed, ttype, direction) VALUES ('$target_id', $speed, '$target_type', $direction);"

	sys_id=$(get_system_id "$system_id")

	sqlite3 "$DB_FILE" "INSERT INTO detections (target_id, system_id, timestamp) VALUES ('$target_id', $sys_id, '$timestamp');"

	rm -f "$file"
}

# Функция обработки файла стрельбы
process_shooting() {
	local decrypted_content="$1"
	local file="$2"

	timestamp=$(echo "$decrypted_content" | cut -d' ' -f1,2)
	system_id=$(echo "$decrypted_content" | cut -d' ' -f3)
	target_id=$(echo "$decrypted_content" | cut -d' ' -f4)
	result=$(echo "$decrypted_content" | cut -d' ' -f5)

	echo "$timestamp $system_id $target_id $result"

	echo "$timestamp $system_id Выстрел по цели ID:$target_id - $([[ "$result" == "1" ]] && echo "уничтожена" || echo "промах")!" >>"$KP_LOG"

	target_exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM targets WHERE id='$target_id';")

	if [[ "$target_exists" -eq 0 ]]; then
		continue
	fi

	sys_id=$(get_system_id "$system_id")

	sqlite3 "$DB_FILE" "INSERT INTO shooting (target_id, system_id, result, timestamp) VALUES ('$target_id', $sys_id, $result, '$timestamp');"

	rm -f "$file"
}

# Функция обработки пополения боекомплекта
process_ammo() {
	local decrypted_content="$1"
	local file="$2"

	timestamp=$(echo "$decrypted_content" | cut -d' ' -f1,2)
	system_id=$(echo "$decrypted_content" | cut -d' ' -f3)
	count=$(echo "$decrypted_content" | cut -d' ' -f4)

	echo "$timestamp $system_id $count"

	echo "$timestamp $system_id Боекомплект обновлен. Загружено $count снарядов!" >>"$KP_LOG"

	sys_id=$(get_system_id "$system_id")

	sqlite3 "$DB_FILE" "INSERT INTO ammo (system_id, count, timestamp) VALUES ($sys_id, $count, '$timestamp');"

	rm -f "$file"
}

declare -A systems_map=(
	["zrdn1"]="ЗРДН1"
	["zrdn2"]="ЗРДН2"
	["zrdn3"]="ЗРДН3"
	["spro"]="СПРО"
	["rls1"]="РЛС1"
	["rls2"]="РЛС2"
	["rls3"]="РЛС3"
)

declare -A system_status

for key in "${!systems_map[@]}"; do
	system_status["$key"]=1 # 1 - работает
done

check_systems() {
	while true; do
		for key in "${!systems_map[@]}"; do
			if [[ ! -f "$CHECK_DIR/ping_$key" ]]; then
				touch "$CHECK_DIR/ping_$key"
			fi
		done

		sleep 30

		for key in "${!systems_map[@]}"; do
			if [[ -f "$CHECK_DIR/ping_$key" ]]; then
				# Если система впервые перестала работать, выводим сообщение
				if [[ ${system_status[$key]} -eq 1 ]]; then
					check_time=$(date '+%d-%m %H:%M:%S.%3N')
					echo "$check_time ${systems_map[$key]} работоспособность потеряна!"
					echo "$check_time ${systems_map[$key]} работоспособность потеряна!" >>"$KP_LOG"
					system_status["$key"]=0 # Отмечаем как неработающую
				fi
			else
				# Если система была неработающей, но теперь отвечает, выводим сообщение о восстановлении
				if [[ ${system_status[$key]} -eq 0 ]]; then
					check_time=$(date '+%d-%m %H:%M:%S.%3N')
					echo "$check_time ${systems_map[$key]} работоспособность восстановлена!"
					echo "$check_time ${systems_map[$key]} работоспособность восстановлена!" >>"$KP_LOG"
					system_status["$key"]=1 # Отмечаем как работающую
				fi
			fi
			rm -f "$CHECK_DIR/pong_$key"
		done

		sleep 30
	done
}

initialize_database
mkdir -p "$DETECTIONS_DIR" "$SHOOTING_DIR" "$AMMO_DIR" "$CHECK_DIR"

check_systems &

echo "Мониторинг файлов в $DETECTIONS_DIR, $SHOOTING_DIR и $AMMO_DIR"
while true; do
	for file in "$DETECTIONS_DIR"/* "$SHOOTING_DIR"/* "$AMMO_DIR/"*; do
		[[ -f "$file" ]] || continue

		decrypted_content=$(decrypt_and_verify_message "$file") || continue

		if [[ "$file" == "$DETECTIONS_DIR/"* ]]; then
			process_detection "$decrypted_content" "$file"
		elif [[ "$file" == "$SHOOTING_DIR/"* ]]; then
			process_shooting "$decrypted_content" "$file"
		elif [[ "$file" == "$AMMO_DIR/"* ]]; then
			process_ammo "$decrypted_content" "$file"
		fi
	done
	sleep 0.5
done
