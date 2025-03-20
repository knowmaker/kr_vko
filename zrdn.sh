#!/bin/bash
# 1. Чистить файл БД перед созданием
# 2. Печатать, если промах
# 3. Правильно категорировать цели
# 4. Добавить миллисекунды
# 5. Заменить функцию mapfile, если можно. Убрать grep c regexp
# 6. Не вписывать в слова АТАКУЕМ в название цели

# Координаты и радиус действия ЗРДН
ZRDN_X=9200000
ZRDN_Y=4500000
ZRD_RADIUS=2000000  # Радиус в метрах

# Каталоги
TARGETS_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"

# Путь к файлу с обработанными целями
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROCESSED_FILES="$SCRIPT_DIR/temp/zrdn_processed_files.txt"
touch "$PROCESSED_FILES"

# Боезапас и время пополнения
MISSILES=20
RELOAD_TIME=10  # Время до пополнения (в секундах)
LAST_RELOAD_TIME=0  # Временная метка последней перезарядки

# Количество файлов для анализа
MAX_FILES=50

# Ассоциативные массивы
declare -A TARGET_COORDS
declare -A TARGET_TYPE
declare -A TARGET_STATUS

# Функция вычисления расстояния (используем bc)
distance() {
    local x1=$1 y1=$2 x2=$3 y2=$4
    local dx=$((x2 - x1))
    local dy=$((y2 - y1))
    echo "scale=2; sqrt($dx * $dx + $dy * $dy)" | bc
}

# Функция для определения типа цели по скорости
get_target_type() {
    local speed=$1
    if (( $(echo "$speed >= 8000" | bc -l) )); then
        echo "ББ бал. ракеты (НЕ АТАКУЕМ)"
    elif (( $(echo "$speed >= 250" | bc -l) )); then
        echo "Крылатая ракета (АТАКА)"
    else
        echo "Самолет (АТАКА)"
    fi
}

# Функция для декодирования ID цели из имени файла
decode_target_id() {
    local filename=$1
    local decoded_hex=""
    for ((i=2; i<=${#filename}; i+=4)); do
        decoded_hex+="${filename:$i:2}"
    done
    echo -n "$decoded_hex" | xxd -r -p
}

echo "ЗРДН 1 запущена!"
while true; do
    current_time=$(date +%s)

    # Проверяем пополнение боезапаса
    if (( MISSILES == 0 )) && (( current_time - LAST_RELOAD_TIME >= RELOAD_TIME )); then
        MISSILES=20
        LAST_RELOAD_TIME=$current_time
        echo "$(date '+%H:%M:%S') Боезапас пополнен!"
    fi

    unset FIRST_TARGET_FILE
    declare -A FIRST_TARGET_FILE
    found_second_file=false

    while ! $found_second_file; do
        # Получаем последние MAX_FILES файлов, отсортированные по времени создания
        mapfile -t latest_files < <(find "$TARGETS_DIR" -type f -printf "%T@ %p\n" | sort -nr | head -n "$MAX_FILES" | awk '{print $2}')

        for target_file in "${latest_files[@]}"; do
            filename=$(basename "$target_file")

            # Пропускаем уже обработанные файлы
            if grep -qFx "$filename" "$PROCESSED_FILES"; then
                continue
            fi

            if [[ ${#filename} -le 2 ]]; then
                echo "$filename" >> "$PROCESSED_FILES"
                continue
            fi

            target_id=$(decode_target_id "$filename")
            #echo "$target_id"
            # Если для этой цели уже был найден файл — завершаем поиск
            if [[ -n "${FIRST_TARGET_FILE[$target_id]}" ]]; then
                found_second_file=true
                break
            fi

            # Запоминаем первый найденный файл для цели
            FIRST_TARGET_FILE["$target_id"]="$target_file"
            echo "$filename" >> "$PROCESSED_FILES"

            x=$(grep -oP 'X:\s*\K\d+' "$target_file")
            y=$(grep -oP 'Y:\s*\K\d+' "$target_file")

            dist_to_target=$(distance "$ZRDN_X" "$ZRDN_Y" "$x" "$y")
            if (( $(echo "$dist_to_target <= $ZRD_RADIUS" | bc -l) )); then
                if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then

                    if [[ "${TARGET_TYPE[$target_id]}" == *"НЕ АТАКУЕМ"* ]]; then
                        continue
                    fi

                    if [[ -z "${TARGET_TYPE[$target_id]}" ]]; then
                        prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
                        prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

                        speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
                        target_type=$(get_target_type "$speed")
                        TARGET_TYPE["$target_id"]="$target_type"

                        if [[ "${TARGET_TYPE[$target_id]}" == *"НЕ АТАКУЕМ"* ]]; then
                            continue
                        fi

                        echo "$(date '+%H:%M:%S') Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
                    fi

                    if [[ "$target_type" == *"АТАКА"* ]]; then
                        if (( MISSILES > 0 )); then
                            echo "$(date '+%H:%M:%S') Атака цели ID:$target_id - Выстрел!"
                            echo "# ( ЗРДН 1 )" > "$DESTROY_DIR/$target_id"
                            ((MISSILES--))
                            TARGET_STATUS["$target_id"]=1

                            if (( MISSILES == 0 )); then
                                LAST_RELOAD_TIME=$(date +%s)
                                echo "$(date '+%H:%M:%S') Боезапас исчерпан! Начинается перезарядка"
                            fi
                        else
                            echo "$(date '+%H:%M:%S') Невозможно атаковать ID:$target_id - Боезапас исчерпан!"
                        fi
                    fi
                fi
                TARGET_COORDS["$target_id"]="$x,$y"
            fi
        done

        if ! $found_second_file; then
            sleep 0.1
        fi
    done

    for id in "${!TARGET_COORDS[@]}"; do
        if [[ -z "${FIRST_TARGET_FILE[$id]}" ]]; then
            if [[ "${TARGET_STATUS[$id]}" -eq 1 ]]; then
                echo "$(date '+%H:%M:%S') Цель ID:$id поражена ЗРДН 1"
            else
                echo "$(date '+%H:%M:%S') Цель ID:$id исчезла из зоны контроля"
            fi
            unset TARGET_COORDS["$id"]
            unset TARGET_TYPE["$id"]
            unset TARGET_STATUS["$id"]
        fi
    done
done

