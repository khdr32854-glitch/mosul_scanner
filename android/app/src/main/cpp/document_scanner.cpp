#include "document_scanner.h"
#include <opencv2/opencv.hpp>
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <vector>
#include <cmath>
#include <cstdlib>
#include <cstring>

using namespace cv;
using namespace std;

// ──────────────────────────────────────────────
// ترتيب النقاط الأربع: TL, TR, BR, BL
// ──────────────────────────────────────────────
static void order_points(vector<Point2f>& pts) {
    if (pts.size() != 4) return;
    
    // ترتيب حسب y (الأعلى أولاً)
    sort(pts.begin(), pts.end(), [](const Point2f& a, const Point2f& b) {
        return a.y < b.y;
    });
    
    vector<Point2f> top = {pts[0], pts[1]};
    vector<Point2f> bottom = {pts[2], pts[3]};
    
    // Top: الأصغر x = TL
    sort(top.begin(), top.end(), [](const Point2f& a, const Point2f& b) {
        return a.x < b.x;
    });
    // Bottom: الأكبر x = BR
    sort(bottom.begin(), bottom.end(), [](const Point2f& a, const Point2f& b) {
        return a.x > b.x;
    });
    
    pts = {top[0], top[1], bottom[0], bottom[1]};
}

// ──────────────────────────────────────────────
// كشف الزوايا
// ──────────────────────────────────────────────
int detect_document_corners(const uint8_t* pixels, int width, int height, float corners[8]) {
    if (!pixels || width < 100 || height < 100) return 0;
    
    try {
        // تحويل إلى Mat
        Mat src(height, width, CV_8UC4, (void*)pixels);
        Mat gray;
        cvtColor(src, gray, COLOR_RGBA2GRAY);
        
        // Gaussian blur
        GaussianBlur(gray, gray, Size(5, 5), 0);
        
        // Canny edge detection
        Mat edges;
        Canny(gray, edges, 75, 200);
        
        // Morphological closing — توصيل الحواف المتقطعة
        Mat kernel = getStructuringElement(MORPH_RECT, Size(7, 7));
        morphologyEx(edges, edges, MORPH_CLOSE, kernel);
        
        // findContours
        vector<vector<Point>> contours;
        vector<Vec4i> hierarchy;
        findContours(edges, contours, hierarchy, RETR_LIST, CHAIN_APPROX_SIMPLE);
        
        double maxArea = 0;
        vector<Point> bestContour;
        
        for (size_t i = 0; i < contours.size(); i++) {
            double area = contourArea(contours[i]);
            double imgArea = width * height;
            
            // تجاهل الصغيرة جداً والكبيرة جداً
            if (area < imgArea * 0.08 || area > imgArea * 0.95) continue;
            
            double peri = arcLength(contours[i], true);
            vector<Point> approx;
            approxPolyDP(contours[i], approx, 0.02 * peri, true);
            
            if (approx.size() == 4 && area > maxArea) {
                maxArea = area;
                bestContour = approx;
            }
        }
        
        if (bestContour.empty()) return 0;
        
        // تحويل إلى Point2f وترتيب
        vector<Point2f> pts;
        for (const auto& p : bestContour) {
            pts.push_back(Point2f(p.x, p.y));
        }
        order_points(pts);
        
        // إرجاع النسب
        for (int i = 0; i < 4; i++) {
            corners[i * 2]     = pts[i].x / (float)width;
            corners[i * 2 + 1] = pts[i].y / (float)height;
        }
        
        return 1;
    } catch (...) {
        return 0;
    }
}

// ──────────────────────────────────────────────
// تحسين CLAHE
// ──────────────────────────────────────────────
static void apply_clahe(Mat& src) {
    Mat lab;
    cvtColor(src, lab, COLOR_RGB2Lab);
    
    vector<Mat> channels;
    split(lab, channels);
    
    Ptr<CLAHE> clahe = createCLAHE(2.0, Size(8, 8));
    clahe->apply(channels[0], channels[0]);
    
    merge(channels, lab);
    cvtColor(lab, src, COLOR_Lab2RGB);
}

// ──────────────────────────────────────────────
// تحسين أبيض وأسود
// ──────────────────────────────────────────────
static void apply_bw(Mat& src) {
    Mat gray;
    cvtColor(src, gray, COLOR_RGB2GRAY);
    
    // Gaussian blur خفيف
    GaussianBlur(gray, gray, Size(3, 3), 0);
    
    // Adaptive threshold
    Mat bw;
    adaptiveThreshold(gray, bw, 255, ADAPTIVE_THRESH_GAUSSIAN_C, THRESH_BINARY, 15, 10);
    
    cvtColor(bw, src, COLOR_GRAY2RGB);
}

// ──────────────────────────────────────────────
// تحسين ناعم (white balance + contrast)
// ──────────────────────────────────────────────
static void apply_soft_enhance(Mat& src) {
    // White balance: normalize brightest region
    Mat lab;
    cvtColor(src, lab, COLOR_RGB2Lab);
    vector<Mat> channels;
    split(lab, channels);
    
    // CLAHE on L channel
    Ptr<CLAHE> clahe = createCLAHE(2.0, Size(8, 8));
    clahe->apply(channels[0], channels[0]);
    
    merge(channels, lab);
    cvtColor(lab, src, COLOR_Lab2RGB);
    
    // Slight contrast boost
    src.convertTo(src, -1, 1.08, 6);
}

// ──────────────────────────────────────────────
// تصحيح منظور + تحسين
// ──────────────────────────────────────────────
int warp_and_enhance(const uint8_t* src_pixels, int src_width, int src_height,
                     const float corners[8],
                     uint8_t* dst_pixels, int dst_width, int dst_height,
                     int enhance_mode) {
    if (!src_pixels || !dst_pixels || !corners) return 0;
    
    try {
        Mat src(src_height, src_width, CV_8UC4, (void*)src_pixels);
        
        // نقاط المصدر
        vector<Point2f> src_pts = {
            Point2f(corners[0] * src_width, corners[1] * src_height),
            Point2f(corners[2] * src_width, corners[3] * src_height),
            Point2f(corners[4] * src_width, corners[5] * src_height),
            Point2f(corners[6] * src_width, corners[7] * src_height),
        };
        
        // نقاط الهدف
        vector<Point2f> dst_pts = {
            Point2f(0, 0),
            Point2f(dst_width - 1, 0),
            Point2f(dst_width - 1, dst_height - 1),
            Point2f(0, dst_height - 1),
        };
        
        // Perspective transform
        Mat M = getPerspectiveTransform(src_pts, dst_pts);
        Mat rgb;
        cvtColor(src, rgb, COLOR_RGBA2RGB);
        
        Mat warped;
        warpPerspective(rgb, warped, M, Size(dst_width, dst_height));
        
        // تحسين
        switch (enhance_mode) {
            case 1: apply_soft_enhance(warped); break;
            case 2: apply_bw(warped); break;
            default: break;
        }
        
        // نسخ إلى dst (RGB format)
        Mat rgba;
        cvtColor(warped, rgba, COLOR_RGB2RGBA);
        memcpy(dst_pixels, rgba.data, dst_width * dst_height * 4);
        
        return 1;
    } catch (...) {
        return 0;
    }
}

// ──────────────────────────────────────────────
// قص تلقائي كامل
// ──────────────────────────────────────────────
uint8_t* auto_scan_document(const uint8_t* pixels, int width, int height,
                            int* out_width, int* out_height,
                            int enhance_mode) {
    if (!pixels || !out_width || !out_height) return nullptr;
    
    float corners[8];
    if (!detect_document_corners(pixels, width, height, corners)) {
        // فشل الكشف — نرجع nullptr (الطبقة العليا تستخدم fallback)
        return nullptr;
    }
    
    // حساب أبعاد الصورة الناتجة
    float w1 = sqrt(pow(corners[2]-corners[0], 2) + pow(corners[3]-corners[1], 2));
    float w2 = sqrt(pow(corners[6]-corners[4], 2) + pow(corners[7]-corners[5], 2));
    float h1 = sqrt(pow(corners[4]-corners[0], 2) + pow(corners[5]-corners[1], 2));
    float h2 = sqrt(pow(corners[6]-corners[2], 2) + pow(corners[7]-corners[3], 2));
    
    int dw = max(1, (int)(max(w1, w2) * width + 0.5f));
    int dh = max(1, (int)(max(h1, h2) * height + 0.5f));
    
    // تحديد الحجم الأقصى
    int longest = max(dw, dh);
    if (longest > 3200) {
        float scale = 3200.0f / longest;
        dw = max(1, (int)(dw * scale));
        dh = max(1, (int)(dh * scale));
    }
    
    uint8_t* dst = (uint8_t*)malloc(dw * dh * 4);
    if (!dst) return nullptr;
    
    if (!warp_and_enhance(pixels, width, height, corners, dst, dw, dh, enhance_mode)) {
        free(dst);
        return nullptr;
    }
    
    *out_width = dw;
    *out_height = dh;
    return dst;
}

