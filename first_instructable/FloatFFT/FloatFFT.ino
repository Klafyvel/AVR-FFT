#include "data.h"

int N = 256;
float frequency = 44000; // Actually useless for our test.
byte *buffer;

float sines[] = {
  0,            // sin(-2π) (Actually never used)
  0,            // sin(-π)
 -1.0,          // sin(-π/2)
 -0.70710677,   // sin(-π/4)
 -0.38268346,   // sin(-π/8)
 -0.19509032,   // sin(-π/16)
 -0.09801714,   // sin(-π/32)
 -0.049067676,  // sin(-π/64)
 -0.024541229,  // sin(-π/128)
 -0.012271538   // sin(-π/256)
};
float two_sines_sq[] = {
 0,             // 2sin²(-2π) (Actually never used)
 0,             // 2sin²(-π) 
 2.0,           // 2sin²(-π/2) 
 1.0,           // 2sin²(-π/4) 
 0.29289326,    // 2sin²(-π/8) 
 0.076120466,   // 2sin²(-π/16) 
 0.01921472,    // 2sin²(-π/32) 
 0.0048152735,  // 2sin²(-π/64) 
 0.0012045439,  // 2sin²(-π/128) 
 0.0003011813,  // 2sin²(-π/256) 
};

// our timer
unsigned long timestart;
unsigned long timestop;
unsigned long totaltime;

void setup() 
{
  Serial.begin(115200);  
  while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }
  }
void loop() {
  if (Serial.available() > 0) {
    buffer = (byte*)(&N);
    Serial.readBytes(buffer, sizeof(int));
    Serial.write(buffer, sizeof(int));
    // We can now start the FFT calculation !
    timestart = micros();

    fft(data, N);
    modulus(data, N, frequency);

    timestop = micros();
    totaltime = timestop-timestart;

    // Then we send back the data to the computer.
    Serial.write((byte*)data, sizeof(float)*N);
    // And finally we write the execution time.
    buffer = (byte*)(&totaltime);
    Serial.write(buffer, sizeof(unsigned long));
  }
  else {
    Serial.println("ready");
  }
  delay(100);
}

/* This is a bit uggly and can be replaced efficiently if we 
   always have the same size of array.
   */
uint8_t bit_reverse(const uint8_t nbits, uint8_t val) {
  switch(nbits) {
    case 8:
      val = bit_reverse(4, (val&0xf0)>>4) | (bit_reverse(4, val&0x0f)<<4);
      break;
    case 7:
      val = bit_reverse(3, (val&0x70)>>4) | (val&0x08) | (bit_reverse(3, val&0x07)<<4);
      break;
    case 6:
      val = bit_reverse(3, (val&0x38)>>3) | (bit_reverse(3, val&0x07)<<3);
      break;
    case 5:
      val = bit_reverse(2, (val&0x18)>>3) | (val&0x4) | (bit_reverse(2, val&0x3)<<3);
      break;
    case 4:
      val = bit_reverse(2, (val&0xc)>>2) | (bit_reverse(2, val&0x3)<<2);
      break;
    case 3:
      val = ((val&0x4)>>2) | (val&0x2) | ((val&0x1)<<2);
      break;
    case 2:
      val = ((val&0x2)>>1) | ((val&0x1)<<1);
      break;
    default:
      break;
  }
  return val;
}

void fft(float x[], const int size) {
  if (size == 1)
    return;
  /* indices */
  uint8_t i,j,k,n_1,array_num_bits;
  uint8_t n_2 = 1;
  /* temporary buffers that should be used right away. */
  float tmp,a,b,c,d,k1,k2,k3;
  /* Will store angles, and recursion values for cosine calculation */
  float alpha, beta, cj, sj;

  uint8_t half_size = size >> 1;

  /* How many bits we need to store the positions in half the array.
     This switch could be replaced by a const variable to gain a bit
     of space if we were always computing on the same size of arrays.
  */
 
  switch(size) {
    case 2:
      array_num_bits = 0;
      break;
    case 4:
      array_num_bits = 1;
      break;
    case 8:
      array_num_bits = 2;
      break;
    case 16:
      array_num_bits = 3;
      break;
    case 32:
      array_num_bits = 4;
      break;
    case 64:
      array_num_bits = 5;
      break;
    case 128:
      array_num_bits = 6;
      break;
    case 256:
      array_num_bits = 7;
      break;
    default:
      array_num_bits = 0;
      break;
  }

  /* Reverse-bit ordering */
  for(i=0; i<half_size; ++i) {
    j = bit_reverse(array_num_bits, i);
    
    if(i<j) {
      /* Swapping real part */
      tmp = x[i<<1];
      x[i<<1] = x[j<<1];
      x[j<<1] = tmp;
      /* Swapping imaginary part */
      tmp = x[(i<<1)+1];
      x[(i<<1)+1] = x[(j<<1)+1];
      x[(j<<1)+1] = tmp;
    }
  }

  /* Actual FFT */
  for(i=0; i<array_num_bits; ++i){
    /* n_1 gives the size of the sub-arrays */
    n_1 = n_2; // n_1 = 2^i
    /* n_2 gives the number of steps required to go from one group of sub-arrays to another */
    n_2 = n_2<<1; // n_2 = 2^(i+1)

    alpha = two_sines_sq[i+2];
    beta = sines[i+1];
    /* Those two will store the cosine and sine 2pij/n₂ */
    cj = 1;
    sj = 0;
    /* j will be the index in Xe and Xo */
    for(j=0;j<n_1;j++) {
      /* We combine the jth elements of each group of sub-arrays */
      for(k=j; k<half_size; k+=n_2) {
        /* Now we calculate the next step of the fft process, i.e.
           X[j] = Xᵉ[j] + exp(-2im*pi*j/n₂) * Xᵒ[j]
           X[j+n₂/2] = Xᵉ[j] - exp(-2im*pi*j/n₂) * Xᵒ[j]
        */
        a = x[(k+n_1)<<1];
        b = x[((k+n_1)<<1)+1];
        c = x[k<<1];
        d = x[(k<<1)+1];
        k1 = floatmul(cj , ( a  + b ));
        k2 = floatmul(a , (sj - cj));
        k3 = floatmul(b , (cj + sj));
        tmp = k1 - k3;
        x[k<<1]           = c + tmp; 
        x[(k+n_1)<<1]     = c - tmp; 
        tmp = k1 + k2;
        x[(k<<1)+1]       = d + tmp; 
        x[((k+n_1)<<1)+1] = d - tmp; 
      }
      /* We calculate the next cosine and sine */
      tmp = cj;
      cj = cj - (floatmul(alpha, cj) + floatmul(beta, sj));
      sj = sj - (floatmul(alpha, sj) - floatmul(beta, tmp));
    }
  }

  /* Building the final FT from its entangled version */
  /* Special case n=0 */
  x[0] = x[0] + x[1];
  x[1] = 0;
  alpha = two_sines_sq[array_num_bits+2]; 
  beta = sines[array_num_bits+1]; 
  cj = 1;
  sj = 0;
  for(j=1; j<=(half_size>>1); ++j) {
    /* We calculate the cosine and sine before the main calculation here to compensate for the first
       step of the loop that was skipped.
    */
    tmp = cj;
    cj = cj - (floatmul(alpha, cj) + floatmul(beta, sj));
    sj = sj - (floatmul(alpha, sj) - floatmul(beta, tmp));
    
    a = x[j<<1] + x[(half_size-j)<<1];
    b = x[(j<<1)+1] - x[((half_size-j)<<1)+1];
    c = -x[(j<<1)+1] - x[((half_size-j)<<1)+1];
    d = x[j<<1] - x[(half_size-j)<<1];
    k1 = floatmul(cj , (c + d));
    k2 = floatmul(c , (sj - cj));
    k3 = floatmul(d , (cj + sj));

    tmp = k1 - k3;
    x[j<<1]                 = half( a - tmp );
    x[(half_size-j)<<1]     = half( a + tmp);
    tmp = k1 + k2;
    x[(j<<1)+1]             = half( b - tmp);
    x[((half_size-j)<<1)+1] = half(-b - tmp);
  }
}

/* A fast (and not-so-crapy™) implementation of float multiplication. Sadly, it is not
   precise enough to calculate sines and cosines.
   */
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
    /* Same thing as before for b's mantissa. */
    "mov %A[result],%C[b]" "\n\t"
    "ori %A[result],0x80" "\n\t"
    /* Copy a's exponent to register D of the result. */
    "mov %D[result],%D[a]" "\n\t"
    "mov __tmp_reg__,%C[a]" "\n\t"
    "lsl __tmp_reg__" "\n\t"
    "rol %D[result]" "\n\t"
    /* Check for zero */
    "cpi %D[result], 0" "\n\t"
    "breq result_zero_%=" "\n\t"
    /* Add b's exponent to D register of the result. */
    "mov %C[result],%D[b]" "\n\t"
    "mov __tmp_reg__,%C[b]" "\n\t"
    "lsl __tmp_reg__" "\n\t"
    "rol %C[result]" "\n\t"
    /* Check for zero */
    "cpi %C[result], 0" "\n\t"
    "breq result_zero_%=" "\n\t"
    "jmp result_not_zero_%=" "\n\t"
    "result_zero_%=:" "\n\t"
    "ldi %A[result], 0" "\n\t"
    "ldi %B[result], 0" "\n\t"
    "ldi %C[result], 0" "\n\t"
    "ldi %D[result], 0" "\n\t"
    "jmp clear_and_exit_%=" "\n\t"
    "result_not_zero_%=:" "\n\t"
    "add %D[result],%C[result]" "\n\t"
    /* Now is the right time to remove the bias, to avoid overflow. */
    "subi %D[result],0x7f" "\n\t"
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
    /* clear __zero_reg__ */
    "clear_and_exit_%=:" "\n\t"
    "clr __zero_reg__" "\n\t"
    :
    [result]"+a"(result):
    [a]"r"(a),[b]"r"(b)
  );

  return result;
}

inline float half(float x) {
  asm(
    /* First store to __tmp_reg__ the exponent */
    "mov __tmp_reg__,%D[x]" "\n\t"
    "mov __zero_reg__,%C[x]" "\n\t"
    "lsl __zero_reg__" "\n\t"
    "rol __tmp_reg__" "\n\t"
    /* Then decrement it */
    "dec __tmp_reg__" "\n\t"
    /* And put it back */
    "lsl %D[x]" "\n\t" // store sign in carry
    "ror __tmp_reg__" "\n\t" // put sign in __tmp_reg__ while puting bit 0 of exponent in carry
    "ror __zero_reg__" "\n\t" // put bit 0 of exponent in zero_reg 7th bit
    "mov %C[x], __zero_reg__" "\n\t"
    "mov %D[x], __tmp_reg__" "\n\t"
    "clr __zero_reg__" "\n\t"
    :
    [x]"+a"(x):
     );
  return x;
}

/* 
   Forbidden bit magic to efficiently calculate the modulus of the array. The
   square root is taken here : https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Approximations_that_depend_on_the_floating_point_representation 
   the square method is homemade.

   x is an array of float with x[2i] the real part and x[2i+1] the imaginary part.
   size is the size of the array.
   frequency is the sampling frequency.

   store the modulus of x in x[0:size/2-1]
   return the frequency of the maximum.
 */
float modulus(float x[], const int size, float frequency) {
  uint8_t i, i_maxi;
  float maxi=0;
  unsigned long k;
  for(i=0; i<size/2; i++) {
    /* Bit magic to calculate x[i<<1]^2 */
    k = *(unsigned long *) & x[i<<1];
    k <<= 1;
    k -= 0x3f748868;
    k &= 0x7fffffff;
    x[i] = *(float *) &k;
    /* Bit magic to calculate x[(i<<1)+1]^2 */
    k = *(unsigned long *) & x[(i<<1)+1];
    k <<= 1;
    k -= 0x3f748868;
    k &= 0x7fffffff;
    x[i] += *(float *) &k;
    /* Bits magic to calculate the square root of x[i<<1]^2+x[(i<<1)+1]^2 */
    k = *(unsigned long *) & x[i];
    k -= 0x0084b0d2;
    k >>= 1;
    k += 0x20000000;
    x[i] = *(float *) &k;
    /* Oh yeah, and also look for the maximum */
    if(x[i]>maxi) {
      maxi = x[i];
      i_maxi = i;
    }
  }
  return i_maxi * frequency/size;
}
