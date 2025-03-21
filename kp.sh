#!/bin/bash

DB_FILE="vko.db"
SCRIPT_DIR=$(dirname "$(realpath "$0")")
MESSAGES_DIR="$SCRIPT_DIR/messages"
DETECTIONS_DIR="$MESSAGES_DIR/detections"
SHOOTING_DIR="$MESSAGES_DIR/shooting"

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

# Функция для обработки файлов обнаружений (detections)
process_detections() {
	for file in "$DETECTIONS_DIR"/*; do
        [[ -f "$file" ]] || continue

		decrypted_content=$(decrypt_and_verify_message "$file") || continue

		timestamp=$(echo "$decrypted_content" | cut -d' ' -f1,2)
		system_id=$(echo "$decrypted_content" | cut -d' ' -f3)
		target_id=$(echo "$decrypted_content" | cut -d' ' -f4)
		speed=$(echo "$decrypted_content" | cut -d' ' -f5)
		target_type=$(echo "$decrypted_content" | cut -d' ' -f6-)

		echo "$timestamp $system_id $target_id $speed $target_type"

		sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO targets (id, speed, ttype, direction) VALUES ('$target_id', $speed, '$target_type', NULL);"

		sys_id=$(get_system_id "$system_id")

		sqlite3 "$DB_FILE" "INSERT INTO detections (target_id, system_id, timestamp) VALUES ('$target_id', $sys_id, '$timestamp');"

		rm -f "$file"
	done
}

# Функция для обработки файлов стрельбы (shooting)
process_shooting() {
	for file in "$SHOOTING_DIR"/*; do
		[[ -f "$file" ]] || continue

		decrypted_content=$(decrypt_and_verify_message "$file") || continue

		timestamp=$(echo "$decrypted_content" | cut -d' ' -f1,2)
		system_id=$(echo "$decrypted_content" | cut -d' ' -f3)
		target_id=$(echo "$decrypted_content" | cut -d' ' -f4)
		result=$(echo "$decrypted_content" | cut -d' ' -f5)

		echo "$timestamp $system_id $target_id $result"

		target_exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM targets WHERE id='$target_id';")

		if [[ "$target_exists" -eq 0 ]]; then
			continue
		fi

		sys_id=$(get_system_id "$system_id")

		sqlite3 "$DB_FILE" "INSERT INTO shooting (target_id, system_id, result, timestamp) VALUES ('$target_id', $sys_id, $result, '$timestamp');"

		rm -f "$file"
	done
}

initialize_database
mkdir -p "$DETECTIONS_DIR" "$SHOOTING_DIR"

echo "Мониторинг файлов в $DETECTIONS_DIR и $SHOOTING_DIR"
while true; do
	process_detections
	process_shooting
	sleep 0.5
done
