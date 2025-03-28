#include <iostream>
#include <vector>
#include <random>
#include <chrono>
#include <cstdlib>

using namespace std;
using namespace chrono;

// Функция для замера времени выполнения команды
double measure_execution_time(const string& command) {
    auto start = high_resolution_clock::now();
    system(command.c_str());
    auto end = high_resolution_clock::now();
    
    return duration<double, milli>(end - start).count();
}

int main() {
    const int TEST_CASES = 100;  // Количество тестов
    vector<long long> results_beam, results_beam2;
    random_device rd;
    mt19937 gen(rd());
    uniform_int_distribution<long long> coord(-10000, 10000);
    uniform_int_distribution<long long> angle(0, 360);
    uniform_int_distribution<long long> fov(10, 180);

    double total_time_beam = 0, total_time_beam2 = 0;

    for (int i = 0; i < TEST_CASES; ++i) {
        // Генерируем случайные параметры
        long long x = coord(gen);
        long long y = coord(gen);
        long long rls_x = coord(gen);
        long long rls_y = coord(gen);
        long long alpha = angle(gen);
        long long angle_val = fov(gen);

        string args = to_string(x) + " " + to_string(y) + " " + to_string(rls_x) + " " + 
                      to_string(rls_y) + " " + to_string(alpha) + " " + to_string(angle_val);

        // Замеряем время работы ./beam
        double time_beam = measure_execution_time("./beam " + args);
        total_time_beam += time_beam;

        // Замеряем время работы ./beam2
        double time_beam2 = measure_execution_time("./beam2 " + args);
        total_time_beam2 += time_beam2;

        cout << "Test " << i + 1 << ": beam = " << time_beam << " ms, beam2 = " << time_beam2 << " ms\n";
    }

    cout << "\n=== SUMMARY ===\n";
    cout << "beam  avg time: " << total_time_beam / TEST_CASES << " ms\n";
    cout << "beam2 avg time: " << total_time_beam2 / TEST_CASES << " ms\n";

    if (total_time_beam2 < total_time_beam)
        cout << "✅ beam2 is faster!\n";
    else
        cout << "❌ beam is faster!\n";

    return 0;
}
