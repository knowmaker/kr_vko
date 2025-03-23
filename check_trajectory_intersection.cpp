#include <iostream>
#include <cmath>

long long distance(long long x1, long long y1, long long x2, long long y2) {
    return std::llround(std::sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)));
}

bool check_trajectory_intersection(long long x1, long long y1, long long x2, long long y2, 
                                   long long sx, long long sy, long long radius) {
    long long dx = x2 - x1;
    long long dy = y2 - y1;

    long long numerator = std::abs((dy * sx) - (dx * sy) + (x2 * y1) - (y2 * x1));
    double denominator = std::sqrt(dx * dx + dy * dy);
    double distance_to_line = numerator / denominator;

    long long distance1 = distance(x1, y1, sx, sy);
    long long distance2 = distance(x2, y2, sx, sy);

    return (distance_to_line <= radius) && (distance2 < distance1);
}

int main(int argc, char* argv[]) {
    if (argc != 8) {
        std::cerr << "Usage: " << argv[0] << " x1 y1 x2 y2 sx sy radius\n";
        return 1;
    }

    long long x1 = std::stoi(argv[1]);
    long long y1 = std::stoi(argv[2]);
    long long x2 = std::stoi(argv[3]);
    long long y2 = std::stoi(argv[4]);
    long long sx = std::stoi(argv[5]);
    long long sy = std::stoi(argv[6]);
    long long radius = std::stoi(argv[7]);

    std::cout << check_trajectory_intersection(x1, y1, x2, y2, sx, sy, radius) << std::endl;
    return 0;
}

// g++ -o check_trajectory_intersection check_trajectory_intersection.cpp -O2