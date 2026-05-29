#include "marquee.h"
#include <cstdint>
#include <cstring>

static const char *MESSAGE = "Apple";
static const char *MESSAGE2 = "Banana";
static const int Y_OFFSET = 5;
static const int CHAR_CELL = 4;
static const int GAP_PX = 6;
static const int SCROLL_STEP = 1;

static uint8_t glyph_row(char c, int row) {
  if (c >= 'a' && c <= 'z') {
    c -= 'a' - 'A';
  }

  switch (c) {
  case 'A': {
    const uint8_t rows[5] = {0b010, 0b101, 0b111, 0b101, 0b101};
    return rows[row];
  }
  case 'B': {
    const uint8_t rows[5] = {0b110, 0b101, 0b110, 0b101, 0b110};
    return rows[row];
  }
  case 'D': {
    const uint8_t rows[5] = {0b110, 0b101, 0b101, 0b101, 0b110};
    return rows[row];
  }
  case 'E': {
    const uint8_t rows[5] = {0b111, 0b100, 0b110, 0b100, 0b111};
    return rows[row];
  }
  case 'F': {
    const uint8_t rows[5] = {0b111, 0b100, 0b110, 0b100, 0b100};
    return rows[row];
  }
  case 'I': {
    const uint8_t rows[5] = {0b111, 0b010, 0b010, 0b010, 0b111};
    return rows[row];
  }
  case 'K': {
    const uint8_t rows[5] = {0b101, 0b101, 0b110, 0b101, 0b101};
    return rows[row];
  }
  case 'L': {
    const uint8_t rows[5] = {0b100, 0b100, 0b100, 0b100, 0b111};
    return rows[row];
  }
  case 'N': {
    const uint8_t rows[5] = {0b101, 0b111, 0b111, 0b111, 0b101};
    return rows[row];
  }
  case 'O': {
    const uint8_t rows[5] = {0b111, 0b101, 0b101, 0b101, 0b111};
    return rows[row];
  }
  case 'P': {
    const uint8_t rows[5] = {0b110, 0b101, 0b110, 0b100, 0b100};
    return rows[row];
  }
  case 'R': {
    const uint8_t rows[5] = {0b110, 0b101, 0b110, 0b101, 0b101};
    return rows[row];
  }
  case 'T': {
    const uint8_t rows[5] = {0b111, 0b010, 0b010, 0b010, 0b010};
    return rows[row];
  }
  default: {
    const uint8_t rows[5] = {0b111, 0b001, 0b010, 0b000, 0b010};
    return rows[row];
  }
  }
}

Marquee::Marquee(Platform *p) {
  throttle = 4;
  platform = p;
  offset = 16;
  content_width = strlen(MESSAGE) * CHAR_CELL + 1 + HEART_W + 1 +
                  strlen(MESSAGE2) * CHAR_CELL;
}

void Marquee::update() {
  platform->clear();

  draw_content(offset);
  draw_content(offset + content_width + GAP_PX);

  offset -= SCROLL_STEP;
  if (offset <= -(content_width + GAP_PX)) {
    offset += content_width + GAP_PX;
  }
}

void Marquee::draw_content(int base_x) {
  int cursor = base_x;

  for (int i = 0; MESSAGE[i] != '\0'; i++) {
    draw_char(MESSAGE[i], cursor, Y_OFFSET, WHITE);
    cursor += CHAR_CELL;
  }

  cursor += 1;
  draw_heart(cursor, Y_OFFSET);
  cursor += HEART_W + 1;

  for (int i = 0; MESSAGE2[i] != '\0'; i++) {
    draw_char(MESSAGE2[i], cursor, Y_OFFSET, WHITE);
    cursor += CHAR_CELL;
  }
}

void Marquee::draw_char(char c, int x, int y, int color) {
  for (int sy = 0; sy < 5; sy++) {
    uint8_t row = glyph_row(c, sy);
    for (int sx = 0; sx < 3; sx++) {
      if ((row & (1 << (2 - sx))) && x + sx >= 0 && x + sx <= 15 &&
          y + sy >= 0 && y + sy <= 15) {
        platform->set_dot(x + sx, y + sy, color);
      }
    }
  }
}

void Marquee::draw_heart(int x, int y) {
  for (int sy = 0; sy < HEART_H; sy++) {
    for (int sx = 0; sx < HEART_W; sx++) {
      if (heart[sy][HEART_W - sx - 1] && x + sx >= 0 && x + sx <= 15 &&
          y + sy >= 0 && y + sy <= 15) {
        platform->set_dot(x + sx, y + sy, RED);
      }
    }
  }
}
