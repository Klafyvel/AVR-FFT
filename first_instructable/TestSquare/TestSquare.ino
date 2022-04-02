float x,y;
float r;
unsigned long loops;

float floatmul(float a, float b) {

  /*
TODO: tout passer en assembleur, parce que là on a des optimisations sauvages de GCC.
*/
  /* On réinterprète a et b en entiers de 32 bits pour pouvoir tranquillement
     sélectionner le signe, l'exposant et le bout de mantisse qui nous intéresse.
     */
  uint32_t ia = *(uint32_t*) &a;
  uint32_t ib = *(uint32_t*) &b;
  /* Serial.print("ia = ");
  Serial.println(ia, HEX);
  Serial.print("ib = ");
  Serial.println(ib, HEX); */
  uint16_t ea = (ia >> 23) & 0xff;
  uint16_t eb = (ib >> 23) & 0xff;
  /* Serial.print("ea = ");
  Serial.println(ea, HEX);
  Serial.print("eb = ");
  Serial.println(eb, HEX); */
  /* On va utiliser la capacité de calcul en virgule fixe de notre processeur,
     donc on passe la mantisse en représentation 1.7 non signée.
     */
  uint8_t fa = ((ia >> 16) & 0xff) | 0x80;
  /* Serial.print("fa = ");
  Serial.println(fa, HEX); */
  uint8_t fb = ((ib >> 16) & 0xff) | 0x80;
  /* Serial.print("fb = ");
  Serial.println(fb, HEX); */
  /* Pareil pour le résultat */
  float result = 0.0;
  uint32_t* iresult = (uint32_t*) & result;
  /* Serial.print("iresult = ");
  Serial.println(*iresult, HEX); */
  /* Première approximation (avant normalisation) de l'exposant */
  uint16_t e = ea + eb - 127; 
  /* Serial.print("e = ");
  Serial.println(e, HEX); */
  
  /* Une variable pour stocker le résultat de la multiplication des mantisses.
     Pour rappel la multiplication de deux nombres en représentation 1.7 est un
     nombre en représentation 1.15
     */
  uint16_t tmp = 0;

  /* Do fractional multiply of the two 16-bits mantissa */
  asm (
    "tst %2" "\n\t"
    "breq runaway_zero_%=" "\n\t"
    "tst %3" "\n\t"
    "breq runaway_zero_%=" "\n\t"
    "fmul %2, %3" "\n\t" // Multiplication de la mantisse
    "movw %0, r0" "\n\t" // on sauvegarde le résultat de la multiplication dans r2
    /* Il reste encore à normaliser. On a deux situations : 
          * Si la retenue est non nulle, alors notre résultat est de la forme 
          (en binaire) 11.abcedfghijklmno, donc notre fonction devrait renvoyer 
          quelque chose comme 1.1abcdef et ajouter 1 à l'exposant.
          * Si la retenue est nulle, notre résultat est de la forme 0.000abcdefghijkl,
          et notre fonction devrait renvoyer quelque chose comme a.bcdefgh. Ici le 
          nombre de zéros initiaux est arbitraire.
     */
    /* Si on a une retenue, on branche */
    "test_carry_%=: " "brcs carry_set_%=" "\n\t" 
    /* Sinon on ajoute 1 à l'exposant */
    "inc %1" "\n\t" 
    /* Puis on shift la mantisse. Si le MSB était un 1, cela va mettre le bit
     de la retenue à 1.
     */
    "lsl %A0" "\n\t"
    "rol %B0" "\n\t"
    /* Et on retourne au test de retenue. */
    "rjmp test_carry_%=" "\n\t"
    /* Quand on arrive là, on a une retenue, donc un nombre de la forme 
       1a.bcdefghijklmnop. 
       Il reste à décrémenter l'exposant et renvoyer la mantisse
       (1.)abcdefghijklmnop.
       */
    "carry_set_%=: " "dec %1" "\n\t"
    /* Un échappatoire quand on a une mantisse nulle */
    "runaway_zero_%=: " "\n\t"
    :
    "+r"(tmp), "+r"(e):
    "a"(fa), "a"(fb):
  );
  /* Serial.print("tmp = ");
  Serial.println(tmp, HEX);
  Serial.print("e = ");
  Serial.println(e, HEX); */

  /* On reconstruit le résultat, en prenant soin d'avoir le bon signe. */
  *iresult = ((ia & 0x80000000)^(ib & 0x80000000)) | ((uint32_t)e << 23) | ((uint32_t)tmp<<7);
  /* Serial.print("iresult = ");
  Serial.println(*iresult, HEX); */

  return result;
}

void setup() {
  Serial.begin(115200);
  while(!Serial) {;}
  Serial.println("Float multiply");

}

void loop() {
  loops = 0;
  x = 1.5;
  r = 2.0;
  // TCNT0 is the timer used to compute milliseconds and drive PWM0.
  // It is an 8 bit value that increments every 64 clock cycles and
  // rolls over from 255 to 0.
  //
  // We repeatedly run the test code as the timer goes from 156 through 255
  // which gives use 64*100 clock cycles.
  //
  // In practice this works for timing operations that take from 1 to 
  // hundreds of clock cycles. The results get a little chunky after that
  // since the last one will have gone a fair bit past the end period.
  //
  while( TCNT0 != 155);        // wait for 155 to start
  while( TCNT0 == 155);        // wait until 155 ends
  
  cli(); // turn off interrupts
  while( TCNT0 > 150 ) {       // that 150 acknowledges we may miss 0
    r = floatmul(x, r);
    loops++;
  }
  sei(); // turn interrupts back on
  Serial.print("loops: ");
  Serial.print(loops,DEC);
  Serial.print(" clocks: ");
  Serial.print( (int) (( 100UL*64UL) / loops) - 8 /* empty loop cost */, DEC);
  Serial.println();
  Serial.print("x: ");
  Serial.print(x);
  Serial.print("y: ");
  Serial.print(y);
  Serial.print("x*y: ");
  Serial.println(r);
  delay(2000);
}
