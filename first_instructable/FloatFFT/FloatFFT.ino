#include <math.h> // M_PI, sin, cos, sqrt

#include "data.h"

int N = 256;
float frequency = 44000; // Actually useless for our test.

float sines[] = {
  0,            // sin(-2π)
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
 0,             // 2sin²(-2π) 
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

void(* reset) (void) = 0; //declare reset function @ address 0

void setup() 
{
  Serial.begin(115200);  
  while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }
  Serial.println("FFT test program.");
  Serial.println(N, DEC);
  // We can now start the FFT calculation !
  timestart = micros();

  fft(data, N);
  modulus(data, N, frequency);

  timestop = micros();
  totaltime = timestop-timestart;
  Serial.println(N, DEC);
  Serial.println("result");

  // Then we send back the data to the computer.

  for(int i=0; i<N; i++) {
    Serial.println(((unsigned long*)data)[i], HEX);
  }
  // And finally we write the execution time.
  Serial.println("Time");
  Serial.println(totaltime, DEC);
  Serial.println("done");
}
void loop() {
  
  delay(500);
}

/* This is a bit uggly and can be replaced efficiently if we 
   always have the same size of array.
   */
uint8_t bit_reverse(uint8_t nbits, uint8_t val) {
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

/* float unsave_divide_by_two(float x) {
  unsigned long i = *(unsigned long*) &x;

} */

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
        k1 = cj * ( a  + b  );
        k2 = a  * ( sj - cj );
        k3 = b  * ( cj + sj );
        tmp = k1 - k3;
        x[k<<1]           = c + tmp; 
        x[(k+n_1)<<1]     = c - tmp; 
        tmp = k1 + k2;
        x[(k<<1)+1]       = d + tmp; 
        x[((k+n_1)<<1)+1] = d - tmp; 
      }
      /* We calculate the next cosine and sine */
      tmp = cj;
      cj = cj - (alpha*cj + beta*sj);
      sj = sj - (alpha*sj - beta*tmp);
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
    cj = cj - (alpha*cj + beta*sj);
    sj = sj - (alpha*sj - beta*tmp);
    
    a = x[j<<1] + x[(half_size-j)<<1];
    b = x[(j<<1)+1] - x[((half_size-j)<<1)+1];
    c = -x[(j<<1)+1] - x[((half_size-j)<<1)+1];
    d = x[j<<1] - x[(half_size-j)<<1];
    k1 = cj * (c + d);
    k2 = c * (sj - cj);
    k3 = d * (cj + sj);

    tmp = k1 - k3;
/* TODO: on doit pouvoir optimiser le *0.5 en opérations bit à bit */
    x[j<<1]                 = ( a - tmp ) * 0.5;
    x[(half_size-j)<<1]     = ( a + tmp ) * 0.5; 
    tmp = k1 + k2;
    x[(j<<1)+1]             = ( b - tmp ) * 0.5;
    x[((half_size-j)<<1)+1] = (-b - tmp ) * 0.5;
  }
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
