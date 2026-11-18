#include <iostream>
#include <string>
using namespace std;

struct Pixel {
    int r, g, b;
};

const int H = 3, W = 5;

void printImage(Pixel img[H][W]) {
    for (int i = 0; i < H; i++) {
        for (int j = 0; j < W; j++)
            cout << "(" << img[i][j].r << "," << img[i][j].g << "," << img[i][j].b << ") ";
        cout << endl;
    }
}

int main() {
    // 2D array of pixels (3 rows x 5 columns)
    Pixel img[H][W] = {
        {{142, 87, 201}, {56, 233, 18},  {99, 170, 74},  {255, 12, 130}, {64, 191, 37}},
        {{208, 45, 160}, {73, 118, 222}, {30, 149, 91},  {120, 65, 200}, {11, 240, 99}},
        {{180, 33, 76},  {5, 150, 250},  {88, 127, 14},  {199, 60, 143}, {46, 222, 9}}
    };

    cout << "Original image:" << endl;
    printImage(img);

    string message = "DSA";

    // Step 1: convert message to bits
    int bits[100];
    int total = 0;
    for (char c : message) {
        for (int i = 7; i >= 0; i--) {
            bits[total++] = (c >> i) & 1;
        }
    }

    // Step 2: embed bits into the LSB of R, G, B (row by row)
    int k = 0;
    for (int i = 0; i < H; i++) {
        for (int j = 0; j < W; j++) {
            if (k < total) img[i][j].r = (img[i][j].r & 0xFE) | bits[k++];
            if (k < total) img[i][j].g = (img[i][j].g & 0xFE) | bits[k++];
            if (k < total) img[i][j].b = (img[i][j].b & 0xFE) | bits[k++];
        }
    }

    cout << "\nImage after embedding:" << endl;
    printImage(img);

    // Step 3: extract the LSBs in the same order
    int got[100];
    int n = 0;
    for (int i = 0; i < H; i++) {
        for (int j = 0; j < W; j++) {
            if (n < total) got[n++] = img[i][j].r & 1;
            if (n < total) got[n++] = img[i][j].g & 1;
            if (n < total) got[n++] = img[i][j].b & 1;
        }
    }

    // Step 4: group every 8 bits back into a character
    string result = "";
    for (int i = 0; i < total; i += 8) {
        int value = 0;
        for (int b = 0; b < 8; b++) {
            value = value * 2 + got[i + b];
        }
        result += (char)value;
    }

    cout << "\nExtracted message: " << result << endl;
    return 0;
}