#pragma once

#include "screen.h"
#include <bitset>

#define HEART_H 5
#define HEART_W 5

class Marquee : public Screen {
private:
  Platform *platform;
  int offset;
  int content_width;
  std::bitset<HEART_W> const heart[HEART_H]{
      std::bitset<HEART_W>("01010"),
      std::bitset<HEART_W>("11111"),
      std::bitset<HEART_W>("11111"),
      std::bitset<HEART_W>("01110"),
      std::bitset<HEART_W>("00100"),
  };

  void draw_content(int base_x);
  void draw_char(char c, int x, int y, int color);
  void draw_heart(int x, int y);

public:
  Marquee(Platform *p);
  void update();
};
