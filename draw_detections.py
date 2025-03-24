import sqlite3
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import os

# Пути к файлам
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
DB_FILE = os.path.join(SCRIPT_DIR, "db", "vko.db")

# Функция определения типа цели по скорости
def get_target_type(speed):
    if speed >= 8000:
        return "ББ БР", "red"  # Баллистическая ракета (красный)
    elif speed >= 250:
        return "Крылатая ракета", "blue"  # Крылатая ракета (синий)
    else:
        return "Самолет", "green"  # Самолет (зеленый)

# Читаем данные из базы
def read_detections():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    query = """
    SELECT d.x, d.y, t.speed
    FROM detections d
    JOIN targets t ON d.target_id = t.id
    """
    
    cursor.execute(query)
    data = cursor.fetchall()
    conn.close()
    
    return data

# Функция построения карты обнаруженных целей
def plot_detections():
    detections = read_detections()

    if not detections:
        print("Нет данных для отображения.")
        return

    plt.figure(figsize=(13, 9))
    ax = plt.gca()

    # Радиолокационные зоны
    zrdn = [
        (6250000, 3850000, 350000),
        (9200000, 4600000, 500000),
        (11000000, 5000000, 600000)
    ]

    spro = [
        (3150000, 3750000, 1200000)
    ]
    
    for x, y, radius in zrdn:
        circle = plt.Circle((x, y), radius, color="green", alpha=0.3, fill=True)
        ax.add_patch(circle)

    for x, y, radius in spro:
        circle = plt.Circle((x, y), radius, color="red", alpha=0.3, fill=True)
        ax.add_patch(circle)

    # Секторы (x, y, radius, угол между осью X и биссектрисой, угол обзора)
    sectors = [
        (6150000, 3700000, 4000000, 270, 200),
        (3200000, 3000000, 3500000, 180, 120),
        (12000000, 5000000, 6000000, 135, 90)
    ]

    for x, y, radius, direction, angle in sectors:
        start_angle = direction - angle / 2  # Начальный угол сектора
        end_angle = direction + angle / 2  # Конечный угол сектора
        wedge = patches.Wedge((x, y), radius, start_angle, end_angle, color="blue", alpha=0.2)
        ax.add_patch(wedge)

    # Отображаем точки обнаруженных целей
    for x, y, speed in detections:
        target_type, color = get_target_type(speed)
        plt.scatter(x, y, c=color, label=target_type, edgecolors="black", alpha=0.7)

    # Настройки графика
    plt.xlim(0, 13000000)
    plt.ylim(0, 9000000)
    plt.xlabel("X (точки)")
    plt.ylabel("Y (точки)")
    plt.title("Карта обнаруженных целей")

    ax.set_xticks(range(0, 14000000, 1000000))  # Шаг 1 000 000 по X
    ax.set_yticks(range(0, 10000000, 1000000))  # Шаг 1 000 000 по Y
    ax.ticklabel_format(style="plain")  # Отключаем экспоненциальный формат
    
    # Убираем дублирующиеся легенды
    handles, labels = plt.gca().get_legend_handles_labels()
    unique_labels = dict(zip(labels, handles))
    plt.legend(unique_labels.values(), unique_labels.keys(), loc="upper right")

    plt.grid(True, linestyle="--", linewidth=0.5)
    plt.show()

if __name__ == "__main__":
    plot_detections()
