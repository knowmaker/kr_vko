#include <iostream>
#include <cmath>

long long distance(long long x1, long long y1, long long x2, long long y2) {
    return std::llround(std::sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)));
}

int main(int argc, char* argv[]) {
    if (argc != 5) {
        std::cerr << "Usage: " << argv[0] << " x1 y1 x2 y2\n";
        return 1;
    }

    long long x1 = std::stoll(argv[1]);
    long long y1 = std::stoll(argv[2]);
    long long x2 = std::stoll(argv[3]);
    long long y2 = std::stoll(argv[4]);

    std::cout << distance(x1, y1, x2, y2) << std::endl;
    return 0;
}
