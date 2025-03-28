#include <iostream>
#include <cmath>

bool beam(long long x, long long y, long long rls_x, long long rls_y, long long alpha, long long angle) {
    // Переводим направление антенны из градусов в радианы
    double alpha_rad = alpha * M_PI / 180.0;
    double half_angle_rad = (angle / 2.0) * M_PI / 180.0;

    // Вектор направления антенны
    double beam_dx = std::cos(alpha_rad);
    double beam_dy = std::sin(alpha_rad);

    // Вектор до цели
    double target_dx = x - rls_x;
    double target_dy = y - rls_y;
    double target_length = std::sqrt(target_dx * target_dx + target_dy * target_dy);

    if (target_length == 0) return true; // Если цель совпадает с РЛС

    // Нормализуем вектор цели
    target_dx /= target_length;
    target_dy /= target_length;

    // Косинус угла между векторами
    double dot_product = beam_dx * target_dx + beam_dy * target_dy;

    // Проверяем, лежит ли цель в секторе
    return dot_product >= std::cos(half_angle_rad);
}

int main(int argc, char* argv[]) {
    if (argc != 7) {
        std::cerr << "Usage: " << argv[0] << " x y rls_x rls_y alpha angle\n";
        return 1;
    }

    long long x = std::stoi(argv[1]);
    long long y = std::stoi(argv[2]);
    long long rls_x = std::stoi(argv[3]);
    long long rls_y = std::stoi(argv[4]);
    long long alpha = std::stoi(argv[5]);
    long long angle = std::stoi(argv[6]);

    std::cout << beam(x, y, rls_x, rls_y, alpha, angle) << std::endl;
    return 0;
}
