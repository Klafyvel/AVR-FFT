float x,y;
float r;
unsigned long loops;

#define BIAS_MUL 0

float floatmul(float a, float b) {
  float result = 0;

  asm (
    /* First step : manage the sign of the product, and store it in flag T.*/
    "mov __tmp_reg__,%D[a]" "\n\t"
    "eor __tmp_reg__,%D[b]" "\n\t"
    "bst __tmp_reg__,7" "\n\t"
    /* Second step : prepare the mantissa under the 1.7 form, and isolate the exponents. */
    /* We copy the high byte of a's mantissa in register B of the result,
       and put it in the 1.7 form.
       */
    "mov %B[result],%C[a]" "\n\t"
    "ori %B[result],0x80" "\n\t"
    /* Copy a's exponent to register D of the result. */
    "mov %D[result],%D[a]" "\n\t"
    "mov __tmp_reg__,%C[a]" "\n\t"
    "lsl __tmp_reg__" "\n\t"
    "rol %D[result]" "\n\t"
    /* Now is the right time to remove the bias, to avoid overflow. */
    "subi %D[result],0x7f" "\n\t"
    /* Same thing as before for b's mantissa. */
    "mov %A[result],%C[b]" "\n\t"
    "ori %A[result],0x80" "\n\t"
    /* Add b's exponent to D register of the result. */
    "mov __zero_reg__,%D[b]" "\n\t"
    "mov __tmp_reg__,%C[b]" "\n\t"
    "lsl __tmp_reg__" "\n\t"
    "rol __zero_reg__" "\n\t"
    "add %D[result],__zero_reg__" "\n\t"
    /* Third step : multiply the mantissas. */
    "fmul %A[result], %B[result]" "\n\t" 
    /* save the result in registers A and B of the result. */
    "movw %A[result], __tmp_reg__" "\n\t" 
    /* Fourth step : overcome possible normalization issues. 
       We only need to perform this normalization once.
     */
    "brcs carry_set_%=" "\n\t"
    "lsl %A[result]" "\n\t"
    "rol %B[result]" "\n\t"
    "dec %D[result]" "\n\t"
    /* Fifth step: now, we should have the right exponent in register D and the normalized
       mantissa in registers A and B, and the sign bit in flag T. Time to rebuild everything.
       */
    "carry_set_%= : inc %D[result]" "\n\t"
    /* First, copy the mantissa from registers A and B to registers B and C.
       Note : we don't clean register A afterwards, this means we will have some remains
       of the computation, but we chose to live with that risk.
       We could use the following instruction to avoid that : clr %A[result] .
     */
    "mov %C[result],%B[result]" "\n\t"
    "mov %B[result],%A[result]" "\n\t"
    "clr %A[result]" "\n\t"
    /* Then we right-shift everything to make room for the sign bit. */
    "lsr %D[result]" "\n\t"
    "ror %C[result]" "\n\t"
    "ror %B[result]" "\n\t"
    "ror %A[result]" "\n\t"
    /* And we copy it. */
    "bld %D[result],7" "\n\t"
    /* Last step : a bit of magic to add a bias. 
       We use that occasion to clear __zero_reg__.
     */
#if BIAS_MUL == 1
    "ldi r16, 0x16" "\n\t"
    "add %A[result], r16" "\n\t"
    "ldi r16, 0xdc" "\n\t"
    "adc %B[result], r16" "\n\t"
#endif
    "clr __zero_reg__" "\n\t"
#if BIAS_MUL == 1
    "adc %C[result], __zero_reg__" "\n\t"
    "adc %D[result], __zero_reg__" "\n\t"
#endif
    :
    [result]"+a"(result):
    [a]"r"(a),[b]"r"(b)
#if BIAS_MUL == 1
    :"r16"
#endif
  );

  return result;
}

void setup() {
  Serial.begin(115200);
  while(!Serial) {;}
  Serial.println("Float multiply");
  delay(500);

  unsigned long i,j = 0;

  x = 0.3;
  y = 2.0;
  uint32_t* a = (uint32_t*)(&x);
  uint32_t* b = (uint32_t*)(&y);
  uint32_t* c = (uint32_t*)(&r);

  for(i=0; i<0x800000; i+=0x10000) {
    *a = 0x3f800000 | i;
    for(j=0; j<i; j+=0x10000) {
      *b = 0x3f800000 | j;
      Serial.print(*a, HEX);
      Serial.print(" ");
      Serial.print(*b, HEX);
      Serial.print(" ");
      r = x*y;
      Serial.print(*c, HEX);
      Serial.print(" ");
      r = floatmul(x,y);
      Serial.println(*c, HEX);
    }
  }
}

void loop() {
}
