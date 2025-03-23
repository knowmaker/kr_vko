#include <iostream>
#include <cmath>

bool beam(long long x, long long y, long long rls_x, long long rls_y, long long alpha, long long angle) {
    long long dx = x - rls_x;
    long long dy = y - rls_y;
    
    double angle_to_target = std::atan2(dy, dx) * 180.0 / M_PI;
    if (angle_to_target < 0) angle_to_target += 360;

    double relative_angle = angle_to_target - alpha;
    if (relative_angle > 180) relative_angle -= 360;
    if (relative_angle < -180) relative_angle += 360;

    return (relative_angle >= -angle / 2) && (relative_angle <= angle / 2);
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

// g++ -o beam beam.cpp -O2