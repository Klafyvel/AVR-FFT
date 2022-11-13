#ifndef H_FLOAT_T
#define H_FLOAT_T
union Float_t
{
    Float_t(float num = 0.0f) : f(num) {}
    // Portable extraction of components.
    bool Negative() const { return (i >> 31) != 0; }
    int32_t RawMantissa() const { return i & ((1 << 23) - 1); }
    int32_t RawExponent() const { return (i >> 23) & 0xFF; }
    bool Infinity() const { return i == 0x7f800000 || i == 0xff800000 ;}
    bool NaN() const { return RawExponent() == 0xff && RawMantissa() != 0;}
 
    int32_t i;
    float f;
};
#endif
