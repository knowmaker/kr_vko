import sqlite3
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import os

# Пути к файлам
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
DB_FILE = os.path.join(SCRIPT_DIR, "db", "vko.db")

# Читаем данные из базы с учетом названия системы и типа цели
def read_detections():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    query = """
    SELECT d.x, d.y, t.ttype, s.name
    FROM detections d
    JOIN targets t ON d.target_id = t.id
    JOIN systems s ON d.system_id = s.id
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
    rls = [
        (6150000, 3700000, 4000000, 270, 200),
        (3200000, 3000000, 3500000, 180, 120),
        (12000000, 5000000, 6000000, 135, 90)
    ]

    for x, y, radius, direction, angle in rls:
        start_angle = direction - angle / 2  # Начальный угол сектора
        end_angle = direction + angle / 2  # Конечный угол сектора
        wedge = patches.Wedge((x, y), radius, start_angle, end_angle, color="blue", alpha=0.2)
        ax.add_patch(wedge)

    # Цвета для типов целей
    target_colors = {
        "ББ БР": "red",
        "Крылатая ракета": "blue",
        "Самолет": "green"
    }

    # Отображаем точки обнаруженных целей с учетом типа системы
    for x, y, ttype, system_name in detections:
        color = target_colors.get(ttype, "black")  # Черный цвет по умолчанию для неизвестных целей

        if "ЗРДН" in system_name:
            marker = "s"  # Квадраты для ЗРДН
        elif "СПРО" in system_name:
            marker = "o"  # Кружки для СПРО
        elif "РЛС" in system_name:
            marker = "^"  # Треугольники для РЛС
        else:
            marker = "x"  # По умолчанию — крестики

        plt.scatter(x, y, c=color, marker=marker, label=ttype, edgecolors="black", alpha=0.7)

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
