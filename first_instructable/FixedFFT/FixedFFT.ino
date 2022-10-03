/*

*/
#include <math.h> // abs, min, max
#include "data.h"

typedef int16_t fixed_t;
const fixed_t FIXED_ONE = 0x7fff;
const fixed_t FIXED_ZERO= 0x0000;
const fixed_t FIXED_HALF = 0x4000;
const fixed_t MODULUS_MAGIC = 0x76a1;
const fixed_t ONE_OVER_SQRT_TWO = 0x5a82;
/* bit zero : operation saturated and was down scaled. */
uint8_t fixed_status; 

fixed_t sines[] = {
  0x0000, // sin(-π)
  0x8000, // sin(-π/2)
  0xa57e, // sin(-π/4)
  0xcf04, // sin(-π/8)
  0xe707, // sin(-π/16)
  0xf374, // sin(-π/32)
  0xf9b8, // sin(-π/64)
  0xfcdc, // sin(-π/128)
  0xfe6e  // sin(-π/256)
};
fixed_t two_sines_sq[] = {
  0x7fff, // 2sin²(-π/2) 
  0x7fff, // 2sin²(-π/4) 
  0x257e, // 2sin²(-π/8) 
  0x09be, // 2sin²(-π/16) 
  0x0277, // 2sin²(-π/32) 
  0x009e, // 2sin²(-π/64) 
  0x0028, // 2sin²(-π/128) 
  0x000a  // 2sin²(-π/256) 
};

int N = 256;
float frequency = 44000; // Actually useless for our test.
byte *buffer;

// our timer
unsigned long timestart;
unsigned long timestop;
unsigned long totaltime;

void setup() {
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
    // Serial.println("done");

    timestop = micros();
    totaltime = timestop-timestart;

    // Then we send back the data to the computer.
    Serial.write((byte*)data, sizeof(fixed_t)*N);
    // And finally we write the execution time.
    buffer = (byte*)(&totaltime);
    Serial.write(buffer, sizeof(unsigned long));
  }
  else {
    Serial.println("ready");
  }
  delay(100);

}

uint8_t fft(fixed_t x[], const int size) {
  if(size == 1)
    return 0;

  /* indices */
  uint8_t i,j,k,n_1,array_num_bits;
  uint8_t n_2 = 1;
  /* temporary buffers that should be used right away. */
  fixed_t tmp,a,b,c,d,k1,k2,k3;
  /* Will store angles, and recursion values for cosine calculation */
  fixed_t alpha,beta,cj,sj;
  uint8_t scale = 0;
  uint8_t has_scaled = 0;

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

    alpha = two_sines_sq[i];
    beta = sines[i];
    /* Those two will store the cosine and sine 2pij/n₂ */
    cj = FIXED_ONE;
    sj = FIXED_ZERO;

    // Serial.println("Scaling down");
    /* Scale down the array of data before the pass, to ensure no overflow happens. */
    for(j=0;j<half_size;j++) {
      x[2*j] = fixed_mul(x[2*j], FIXED_HALF);
      x[2*j+1] = fixed_mul(x[2*j+1], FIXED_HALF);
    }
    // Serial.print("Array prior to step ");
    // Serial.println(i, DEC);
    // for(j=0;j<size;j++) {
    //   Serial.println(x[j], DEC);
    // }

    // has_scaled = 0;
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
        k1 =  fixed_mul(cj, fixed_add_saturate(a,  b));
        k2 =  fixed_mul(a,  fixed_add_saturate(sj, -cj));
        k3 =  fixed_mul(b,  fixed_add_saturate(cj, sj));
        tmp = fixed_add_saturate(k1, -k3);
        x[k<<1]           = fixed_add_saturate(c,   tmp); 
        x[(k+n_1)<<1]     = fixed_add_saturate(c,  -tmp); 
        tmp = fixed_add_saturate(k1, k2);
        x[(k<<1)+1]       = fixed_add_saturate(d,  tmp); 
        x[((k+n_1)<<1)+1] = fixed_add_saturate(d, -tmp); 
      }
      /* We calculate the next cosine and sine */
      tmp = cj;
      cj = fixed_add_saturate(cj, -fixed_add_saturate(fixed_mul(alpha, cj), fixed_mul(beta, sj)));
      sj = fixed_add_saturate(sj, -fixed_add_saturate(fixed_mul(alpha, sj), -fixed_mul(beta, tmp)));
    }
  }

    // Serial.println("Array prior to final ");
    // for(j=0;j<size;j++) {
    //   Serial.println(x[j], DEC);
    // }
  for(j=0;j<half_size;j++) {
    x[2*j] = fixed_mul(x[2*j], FIXED_HALF);
    x[2*j+1] = fixed_mul(x[2*j+1], FIXED_HALF);
  }
  /* Building the final FT from its entangled version */
  /* Special case n=0 */
  x[0] = fixed_add_saturate(x[0], x[1]);
  x[1] = FIXED_ZERO;

  alpha = two_sines_sq[array_num_bits]; 
  beta = sines[array_num_bits]; 
  cj = FIXED_ONE;
  sj = FIXED_ZERO;
  for(j=1; j<=(half_size>>1); ++j) {
  /* We calculate the cosine and sine before the main calculation here to compensate for the first
     step of the loop that was skipped.
   */
    tmp = cj;
    cj = fixed_add_saturate(cj, -fixed_add_saturate(fixed_mul(alpha, cj),  fixed_mul(beta, sj)));
    sj = fixed_add_saturate(sj, -fixed_add_saturate(fixed_mul(alpha, sj), -fixed_mul(beta, tmp)));

    a = fixed_add_saturate(x[j<<1], x[(half_size-j)<<1]);
    b = fixed_add_saturate(x[(j<<1)+1], -x[((half_size-j)<<1)+1]);
    c = fixed_add_saturate(-x[(j<<1)+1], -x[((half_size-j)<<1)+1]);
    d = fixed_add_saturate(x[j<<1], -x[(half_size-j)<<1]);
    k1 = fixed_mul(cj , fixed_add_saturate(c, d));
    k2 = fixed_mul(c , fixed_add_saturate(sj, -cj));
    k3 = fixed_mul(d , fixed_add_saturate(cj, sj));

    tmp = fixed_add_saturate(k1, -k3);
    x[j<<1]                 = fixed_mul(fixed_add_saturate( a, - tmp), FIXED_HALF);
    x[(half_size-j)<<1]     = fixed_mul(fixed_add_saturate( a,   tmp), FIXED_HALF);
    tmp = fixed_add_saturate(k1, k2);
    x[(j<<1)+1]             = fixed_mul(fixed_add_saturate( b, - tmp), FIXED_HALF);
    x[((half_size-j)<<1)+1] = fixed_mul(fixed_add_saturate(-b, - tmp), FIXED_HALF);
  }
  return scale;
}

/* This scales down the entire array.
   TODO: maybe this can be efficiently rewritten in assembly.
   */
void scale_down(fixed_t x[], const int size) {
  uint8_t i;
  for(i=0; i<size;i++) {
    x[i] /= 2;
  }
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

/* Signed fractional multiply of two 16-bit numbers with 32-bit result. */
fixed_t fixed_mul(fixed_t a, fixed_t b) {
  fixed_t result;
  asm (
      // We need a register that's always zero
      "clr r2" "\n\t"
      "fmuls %B[a],%B[b]" "\n\t" // Multiply the MSBs
      "movw %A[result],__tmp_reg__" "\n\t" // Save the result
      "mov __tmp_reg__,%B[a]" "\n\t"
      "eor __tmp_reg__,%B[b]" "\n\t"
      "eor __tmp_reg__,%B[result]" "\n\t"
      "fmul %A[a],%A[b]" "\n\t" // Multiply the LSBs
      "adc %A[result],r2" "\n\t" // Do not forget the carry
      "movw r18,__tmp_reg__" "\n\t" // The result of the LSBs multipliplication is stored in temporary registers
      "fmulsu %B[a],%A[b]" "\n\t" // First crossed product
                                  // This will be reported onto the MSBs of the temporary registers and the LSBs
                                  // of the result registers. So the carry goes to the result's MSB.
      "sbc %B[result],r2" "\n\t"
      // Now we sum the cross product
      "add r19,__tmp_reg__" "\n\t"
      "adc %A[result],__zero_reg__" "\n\t"
      "adc %B[result],r2" "\n\t"
      "fmulsu %B[b],%A[a]" "\n\t" // Second cross product, same as first.
      "sbc %B[result],r2" "\n\t"
      "add r19,__tmp_reg__" "\n\t"
      "adc %A[result],__zero_reg__" "\n\t"
      "adc %B[result],r2" "\n\t"
      "clr __zero_reg__" "\n\t"
      :
      [result]"+r"(result):
      [a]"a"(a),[b]"a"(b):
      "r2","r18","r19"
  );
  return result;
}

/* Fixed point addition with saturation to ±1. */
fixed_t fixed_add_saturate(fixed_t a, fixed_t b) {
  fixed_t result;
  asm (
      "movw %A[result], %A[a]" "\n\t"
      "add %A[result],%A[b]" "\n\t" 
      "adc %B[result],%B[b]" "\n\t" 
      "brvc fixed_add_saturate_goodbye" "\n\t"
      "subi %B[result], 0" "\n\t"
      "brmi fixed_add_saturate_plus_one" "\n\t"
      "fixed_add_saturate_minus_one:" "\n\t" 
      "ldi %B[result],0x80" "\n\t"
      "ldi %A[result],0x00" "\n\t"
      "jmp fixed_add_saturate_goodbye" "\n\t"
      "fixed_add_saturate_plus_one:" "\n\t"
      "ldi %B[result],0x7f" "\n\t"
      "ldi %A[result],0xff" "\n\t"
      "fixed_add_saturate_goodbye:" "\n\t"
      :
      [result]"+d"(result):
      [a]"r"(a),[b]"r"(b)
  );

  return result;
}

fixed_t fixed_add_scale(fixed_t a, fixed_t b) {
  fixed_t result = 0;
  fixed_status &= 0xfe;

   asm (
      "andi %[fixed_status],0xfe" "\n\t"
      "movw %A[result], %A[a]" "\n\t"
      "add %A[result],%A[b]" "\n\t" 
      "adc %B[result],%B[b]" "\n\t" 
      "brvc fixed_add_scale_goodbye" "\n\t"
      "ori %[fixed_status],0x1" "\n\t"
      "fixed_add_scale_goodbye:" "\n\t"
      :
      [result]"=r"(result),[fixed_status]"=d"(fixed_status):
      [a]"r"(a),[b]"r"(b)
  );
  if(fixed_status & 0x1) {
    // Serial.println("Going into recursion.");
    result = fixed_add_scale(max(a,b) / 2, min(a,b));
    // Serial.println("Returning from recursion.");
    fixed_status |= 0x01;
  }
  // Serial.print("Fixed status before returning :");
  // Serial.println(fixed_status, BIN);

  return result;
}

/* Approximate modulus with an 8% margin error. 
   See here (http://www.azillionmonkeys.com/qed/sqroot.html#distance)
   for why it works.
   */
float modulus(fixed_t x[], const int size, float frequency) {
  uint8_t i, i_maxi;
  fixed_t a,b;
  fixed_t maxi=0;
  for(i=0; i<size/2; i++) {
    // min((1 / √2)*(|x|+|y|), max (|x|, |y|))
    a = abs(x[2*i]);
    b = abs(x[2*i+1]);
    x[i] = fixed_mul(MODULUS_MAGIC, min(fixed_mul(ONE_OVER_SQRT_TWO, fixed_add_saturate(a, b)), max(a, b)));
    /* Oh yeah, and also look for the maximum */
    if(x[i]>maxi) {
      maxi = x[i];
      i_maxi = i;
    }
  }
  return i_maxi * frequency/size;
}
