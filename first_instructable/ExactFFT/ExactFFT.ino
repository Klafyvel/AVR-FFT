#include <math.h>
#include "data.h"

int N = 256;
float frequency = 44000; // Actually useless for our test.
byte *buffer;

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
  float cj, sj;

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

    /* j will be the index in Xe and Xo */
    for(j=0;j<n_1;j++) {
      /* We combine the jth elements of each group of sub-arrays */
      cj = cos(-2*PI*j/n_2);
      sj = sin(-2*PI*j/n_2);
      for(k=j; k<half_size; k+=n_2) {
        /* Now we calculate the next step of the fft process, i.e.
           X[j] = Xᵉ[j] + exp(-2im*pi*j/n₂) * Xᵒ[j]
           X[j+n₂/2] = Xᵉ[j] - exp(-2im*pi*j/n₂) * Xᵒ[j]
        */
        a = x[(k+n_1)<<1];
        b = x[((k+n_1)<<1)+1];
        c = x[k<<1];
        d = x[(k<<1)+1];
        k1 = cj * (a+b);
        k2 = a * (sj - cj);
        k3 = b * (cj + sj);
        tmp = k1 - k3;
        x[k<<1]           = c + tmp; 
        x[(k+n_1)<<1]     = c - tmp; 
        tmp = k1 + k2;
        x[(k<<1)+1]       = d + tmp; 
        x[((k+n_1)<<1)+1] = d - tmp; 
      }
    }
  }
  // Serial.println(" ");

  /* Building the final FT from its entangled version */
  /* Special case n=0 */
  x[0] = x[0] + x[1];
  x[1] = 0;
  for(j=1; j<=(half_size>>1); ++j) {
    cj = cos(-PI*j/half_size);
    sj = sin(-PI*j/half_size);
    
    a = x[j<<1] + x[(half_size-j)<<1];
    b = x[(j<<1)+1] - x[((half_size-j)<<1)+1];
    c = -x[(j<<1)+1] - x[((half_size-j)<<1)+1];
    d = x[j<<1] - x[(half_size-j)<<1];
    k1 = cj * (c+d);
    k2 = c*(sj-cj);
    k3 = d*(cj+sj);

    tmp = k1 - k3;
    x[j<<1]                 = ( a - tmp ) * 0.5;
    x[(half_size-j)<<1]     = ( a + tmp) * 0.5; 
    tmp = k1 + k2;
    x[(j<<1)+1]             = ( b - tmp) * 0.5;
    x[((half_size-j)<<1)+1] = (-b - tmp) * 0.5;
  }
}

/* 
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
    x[i] = sqrt(x[i<<1]*x[i<<1] + x[(i<<1)+1]*x[(i<<1)+1]);
    /* Oh yeah, and also look for the maximum */
    if(x[i]>maxi) {
      maxi = x[i];
      i_maxi = i;
    }
  }
  return i_maxi * frequency/size;
}

