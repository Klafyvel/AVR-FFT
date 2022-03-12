using LibSerialPort, GLMakie, Statistics

list_ports()

## Setting for the Arduino
portname = "/dev/ttyACM0"
baudrate = 115200

## The test function
"""
Create the test data, N is the number of samples.
"""
function make_data(N)
  x = range(0,12π,length=N)
  x, sin.(x) .+ sin.(2x) .+ sin.(3x)
end

function arduino_debug(sp)
  @info "Arduino said..." readline(sp)
end

## Plotting the test function just to be sure
testx, testy = make_data(2048)

lines(
      testx, testy,
      color=:red, # To match the original article
      axis=(
            xticksvisible=false,
            xticklabelsvisible=false,
            yticksvisible=false,
            yticklabelsvisible=false,
           )
     )

save("test_signal.png", current_figure())
current_figure()

## Conversion to ApproxFFT data

# ApproxFFT wants integers, and integers are encoded on two bytes on Arduino, so 
# we need to create a function that translates the output of `make_data` to 16-bits 
# integers.
function to_16_bits(data)
  # We might as well use the full range of available data.
  mini,maxi = extrema(data)
  avg = mean(data)
  span = maxi-mini
  new_span = ((2^15-1)) - 1 # ApproxFFT does not like negative values.
  round.(Int16, (data .- avg) ./ span .* new_span)
end

testx, testy = make_data(2048)
testinty = to_16_bits(testy)

lines(
      testx, testinty,
      color=:red, # To match the original article
      axis=(
            xticksvisible=false,
            xticklabelsvisible=false,
            yticksvisible=false,
            yticklabelsvisible=false,
           )
     )
##
function write_data_16_bits(N)
  d = make_data(N)[2] |> to_16_bits
  open("ApproxFFT/data.h", write=true) do f
    write(f, "#ifndef H_DATA\n")
    write(f, "#define H_DATA\n")
    write(f, "int data[] = {\n")
    for n ∈ d
      write(f, "$n,\n")
    end
    write(f, "};\n")
    write(f, "#endif H_DATA\n")
  end
end 

write_data_16_bits(256);

## Testing ApproxFFT

approxfft_testsizes = [4,8,16,32,64,128,256]
approxfft_time = [484, 896, 1996, 4364, 10200, 23676, 55736]
approxfft_results = [
                     Int32[
                           1
                           863
                           187
                           413
                          ],
                     Int32[
                           5946
                           14961
                           5840
                           4175
                           312
                           314
                           212
                           3
                          ],
                     Int32[
                           11095
                           10211
                           2064
                           1259
                           948
                           812
                           720
                           633
                           55
                           -57
                           -152
                           -217
                           -245
                           -238
                           -204
                           -156
                          ],
                     Int32[
                           335
                           13238
                           11689
                           9850
                           8709
                           9617
                           8702
                           1316
                           1322
                           4625
                           12445
                           7366
                           4799
                           15510
                           5460
                           7449
                           -13
                           19
                           29
                           12
                           -29
                           -86
                           -145
                           -196
                           -225
                           -229
                           -207
                           -166
                           -117
                           -74
                           -52
                           -62
                          ],
                     Int32[
                           47
                           6147
                           10476
                           7062
                           9944
                           6891
                           1685
                           760
                           419
                           278
                           167
                           95
                           126
                           83
                           96
                           71
                           62
                           43
                           77
                           67
                           32
                           68
                           51
                           42
                           45
                           37
                           45
                           64
                           86
                           12
                           84
                           33
                           -66
                           -147
                           -253
                           -367
                           -471
                           -544
                           -570
                           -540
                           -453
                           -317
                           -148
                           32
                           201
                           337
                           424
                           454
                           428
                           355
                           251
                           137
                           31
                           -50
                           -97
                           -107
                           -85
                           -42
                           7
                           48
                           70
                           67
                           37
                           -13
                          ],
                     Int32[
                           13414
                           9481
                           7493
                           8799
                           5934
                           5660
                           6132
                           5465
                           3305
                           1867
                           3261
                           1698
                           511
                           1219
                           3719
                           3676
                           2713
                           3356
                           1526
                           1608
                           1656
                           675
                           2203
                           1533
                           1126
                           1135
                           576
                           1265
                           2918
                           2098
                           1555
                           4237
                           4201
                           2641
                           1416
                           1004
                           2143
                           1434
                           634
                           1268
                           1798
                           936
                           1555
                           2098
                           263
                           2089
                           2820
                           2059
                           1092
                           2515
                           3165
                           1322
                           989
                           1215
                           1298
                           1926
                           1088
                           525
                           1199
                           1774
                           1628
                           1517
                           682
                           3413
                           -15
                           -72
                           -113
                           -130
                           -121
                           -88
                           -41
                           7
                           41
                           48
                           20
                           -45
                           -140
                           -252
                           -364
                           -454
                           -506
                           -505
                           -446
                           -333
                           -178
                           0
                           177
                           332
                           445
                           504
                           505
                           454
                           363
                           252
                           139
                           44
                           -20
                           -49
                           -42
                           -8
                           40
                           87
                           120
                           130
                           112
                           71
                           15
                           -45
                           -95
                           -125
                           -129
                           -107
                           -65
                           -16
                           27
                           49
                           39
                           -8
                           -89
                           -195
                           -309
                           -413
                           -486
                           -512
                           -483
                           -396
                           -260
                           -91
                          ],
                     Int32[
                           7935
                           4279
                           3513
                           1706
                           844
                           745
                           847
                           1094
                           634
                           516
                           439
                           567
                           640
                           256
                           44
                           607
                           190
                           411
                           369
                           290
                           234
                           623
                           370
                           13
                           252
                           76
                           488
                           183
                           448
                           983
                           238
                           1634
                           568
                           1062
                           174
                           386
                           154
                           63
                           240
                           370
                           347
                           184
                           176
                           199
                           396
                           63
                           279
                           116
                           367
                           367
                           62
                           26
                           237
                           291
                           220
                           410
                           316
                           178
                           616
                           123
                           457
                           591
                           262
                           2493
                           2126
                           835
                           865
                           545
                           418
                           346
                           238
                           189
                           251
                           276
                           187
                           64
                           147
                           157
                           215
                           337
                           348
                           211
                           123
                           41
                           74
                           60
                           346
                           137
                           105
                           243
                           248
                           274
                           710
                           571
                           661
                           911
                           711
                           340
                           490
                           247
                           478
                           178
                           118
                           169
                           193
                           223
                           307
                           221
                           223
                           83
                           154
                           239
                           310
                           280
                           207
                           158
                           183
                           148
                           78
                           247
                           373
                           191
                           495
                           166
                           625
                           254
                           660
                           1642
                           90
                           259
                           395
                           482
                           511
                           485
                           412
                           309
                           194
                           89
                           7
                           -39
                           -49
                           -27
                           15
                           64
                           106
                           128
                           124
                           94
                           44
                           -16
                           -72
                           -113
                           -130
                           -121
                           -88
                           -41
                           7
                           41
                           48
                           20
                           -45
                           -140
                           -253
                           -364
                           -455
                           -506
                           -505
                           -446
                           -333
                           -178
                           0
                           177
                           332
                           445
                           504
                           505
                           454
                           363
                           252
                           139
                           44
                           -21
                           -49
                           -42
                           -8
                           40
                           87
                           120
                           129
                           112
                           71
                           15
                           -45
                           -95
                           -125
                           -129
                           -107
                           -65
                           -16
                           26
                           48
                           38
                           -8
                           -90
                           -195
                           -310
                           -413
                           -486
                           -512
                           -483
                           -396
                           -260
                           -91
                           90
                           259
                           395
                           482
                           511
                           485
                           412
                           309
                           194
                           89
                           7
                           -39
                           -49
                           -27
                           15
                           64
                           106
                           128
                           124
                           94
                           44
                           -16
                           -72
                           -113
                           -130
                           -121
                           -88
                           -41
                           7
                           41
                           48
                           20
                           -45
                           -140
                           -253
                           -364
                           -455
                           -506
                           -505
                           -446
                           -333
                           -178
                           0
                          ]
                    ]

## Create FloatFFT datasets

function write_data_float(N)
  d = make_data(N)[2]
  open("FloatFFT/data.h", write=true) do f
    write(f, "#ifndef H_DATA\n")
    write(f, "#define H_DATA\n")
    write(f, "float data[] = {\n")
    for n ∈ d
      write(f, "$n,\n")
    end
    write(f, "};\n")
    write(f, "#endif H_DATA\n")
  end
end 

write_data_float(256);

## sines precomputation

step_angles = (-2π ./ (2 .^ (0:9))) .|> Float32
sines = sin.(step_angles)


##
floatfft_testsizes =[4,8,16,32,64,128,256]
floatfft_results_raw =[
                    UInt32[
                           0x40955C2A
                           0x40057391
                           0xBFCFE1F4
                           0x3FA765C7
                          ],
                    UInt32[
                           0x41596D18
                           0x408459F7
                           0x3FC13480
                           0x3F8A0FD9
                           0xBFB06E3C
                           0x3F1D7C5F
                           0xBF862602
                           0x3E828DF0
                          ],
                    UInt32[
                           0x4175860C
                           0x41305BC8
                           0x3FE09F6F
                           0x3F61F8E8
                           0x3F1C82FF
                           0x3EFA40AD
                           0x3EDA0E9F
                           0x3ECA26D2
                           0xBF10A128
                           0x3E6F45D0
                           0xBEEDD7F0
                           0x3E1BA6C9
                           0xBED4CA66
                           0x3DBE89E0
                           0xBEC8DE68
                           0x3D35E7D0
                          ],
                    UInt32[

                           0x417B2F78
                           0x4164D6CF
                           0x41472C71
                           0x40C83B00
                           0x4026D002
                           0x3FC4DA0B
                           0x3F860080
                           0x3F469A71
                           0x3F1C1A8D
                           0x3F005164
                           0x3EDABE5F
                           0x3EC04654
                           0x3EADA8C5
                           0x3EA0C48B
                           0x3E984E0C
                           0x3E937FCA
                           0xBF1BF080
                           0x3CE51900
                           0xBF00409D
                           0x3C83373E
                           0xBEDAB146
                           0x3C176360
                           0xBEC04173
                           0x3BAD3C40
                           0xBEADA714
                           0x3B41CE00
                           0xBEA0C404
                           0x3AD07800
                           0xBE984DE8
                           0x3A507000
                           0xBE937FC4
                           0x39A9C000
                          ],
                    UInt32[
                           0x418FBB85
                           0x41E6F281
                           0x4142BE0A
                           0x420070F5
                           0x41946746
                           0x41AB6F86
                           0x40DBCB05
                           0x407BEEDF
                           0x402AFDF6
                           0x3FFCA644
                           0x3FC4BABB
                           0x3F9EE6E1
                           0x3F83EB78
                           0x3F5FD455
                           0x3F414751
                           0x3F29676F
                           0x3F166655
                           0x3F070B72
                           0x3EF4FAF1
                           0x3EE04068
                           0x3ECF0410
                           0x3EC09C53
                           0x3EB488D3
                           0x3EAA6746
                           0x3EA1EC09
                           0x3E9ADC0B
                           0x3E950919
                           0x3E904F31
                           0x3E8C9332
                           0x3E89BF9A
                           0x3E87C53D
                           0x3E8699B9
                           0xBF1606F0
                           0xBD294A80
                           0xBF06B60A
                           0xBD17C96E
                           0xBEF4633C
                           0xBD083C86
                           0xBEDFBB04
                           0xBCF473E0
                           0xBECE9036
                           0xBCDAE43C
                           0xBEC0392A
                           0xBCC358D0
                           0xBEB43569
                           0xBCAD7768
                           0xBEAA2295
                           0xBC98F1E0
                           0xBEA1B4ED
                           0xBC858BC0
                           0xBE9AB145
                           0xBC662140
                           0xBE94E94A
                           0xBC42B400
                           0xBE9038E0
                           0xBC207E00
                           0xBE8C84C8
                           0xBBFE9E00
                           0xBE89B770
                           0xBBBDB400
                           0xBE87C198
                           0xBB7BA800
                           0xBE8698D0
                           0xBAFAD000
                          ],
                    UInt32[
                           0x3DE3B48C
                           0x3EB11592
                           0x3F671D8F
                           0x4280C0DE
                           0x3DE403F1
                           0x3FA19F36
                           0x4280252F
                           0x3F761A3F
                           0x3F764272
                           0x427BCAC4
                           0x404638B8
                           0x3FE6FA5B
                           0x3FAC0A2B
                           0x3F8C6229
                           0x3F703C54
                           0x3F53A01F
                           0x3F3E23AC
                           0x3F2D4C5F
                           0x3F1FAE17
                           0x3F146704
                           0x3F0AE3DE
                           0x3F02BE82
                           0x3EF75D9F
                           0x3EEAFF9D
                           0x3EE012F0
                           0x3ED65A7F
                           0x3ECDA635
                           0x3EC5D059
                           0x3EBEB9AF
                           0x3EB84916
                           0x3EB26A5F
                           0x3EAD0BF7
                           0x3EA81F59
                           0x3EA39845
                           0x3E9F6C9E
                           0x3E9B92E9
                           0x3E9803D3
                           0x3E94B826
                           0x3E91AA53
                           0x3E8ED5E9
                           0x3E8C3533
                           0x3E89C480
                           0x3E878122
                           0x3E856722
                           0x3E8373F1
                           0x3E81A51B
                           0x3E7FF113
                           0x3E7CD77E
                           0x3E79FB77
                           0x3E77598A
                           0x3E74ED36
                           0x3E72B5C1
                           0x3E70B0BC
                           0x3E6EDBC9
                           0x3E6D3461
                           0x3E6BBA31
                           0x3E6A6B3D
                           0x3E69463E
                           0x3E6849D4
                           0x3E677714
                           0x3E66CAEC
                           0x3E66457B
                           0x3E65E66F
                           0x3E65ACD7
                           0xBE69B5B6
                           0x3E71BE92
                           0xBE694F3F
                           0x3E6563CC
                           0xBE68F2F5
                           0x3E59B6A5
                           0xBE689FF8
                           0x3E4EA2E9
                           0xBE685465
                           0x3E441AD5
                           0xBE680F84
                           0x3E3A0EE1
                           0xBE67D140
                           0x3E3072F2
                           0xBE679880
                           0x3E273F26
                           0xBE67649E
                           0x3E1E6618
                           0xBE673500
                           0x3E15E05C
                           0xBE6709C8
                           0x3E0DA895
                           0xBE66E1FE
                           0x3E05B5D2
                           0xBE66BDC9
                           0x3DFC03D8
                           0xBE669C98
                           0x3DED0FA2
                           0xBE667E71
                           0x3DDE84F2
                           0xBE6661E5
                           0x3DD05AC6
                           0xBE6648A8
                           0x3DC287C0
                           0xBE6631EA
                           0x3DB50572
                           0xBE661C27
                           0x3DA7CA76
                           0xBE660908
                           0x3D9AD092
                           0xBE65F7E2
                           0x3D8E1398
                           0xBE65E888
                           0x3D818BD8
                           0xBE65DA14
                           0x3D6A6800
                           0xBE65CE00
                           0x3D520900
                           0xBE65C2CE
                           0x3D39FE98
                           0xBE65B909
                           0x3D223418
                           0xBE65B080
                           0x3D0A9A00
                           0xBE65AA5B
                           0x3CE67690
                           0xBE65A4CB
                           0x3CB800AC
                           0xBE65A080
                           0x3C89BA00
                           0xBE659D25
                           0x3C378388
                           0xBE659A86
                           0x3BB772A2
                          ],
                    UInt32[
                           0x3545A797
                           0x3E9EC979
                           0x3F2A8FB3
                           0x3F8A1736
                           0x3FE3B5BB
                           0x405D6087
                           0x42FE506A
                           0x3FFCBF53
                           0x3C6D508E
                           0x3F8E37E3
                           0x40216C5A
                           0x40BCDAEA
                           0x42FD37C6
                           0x40BDBA3B
                           0x3FF3D67E
                           0x3DCDC9C1
                           0x3FEEBAA2
                           0x40CC700A
                           0x42F7EDA6
                           0x413D9130
                           0x40C9D2C0
                           0x408DA690
                           0x40654E07
                           0x40487044
                           0x4030CDE2
                           0x401A3877
                           0x400A63F7
                           0x3FFEBF89
                           0x3FEE1480
                           0x3FE022E4
                           0x3FD4EF41
                           0x3FCBC37E
                           0x3FC422A2
                           0x3FBDB414
                           0x3FB2C808
                           0x3FA954C4
                           0x3FA11E1C
                           0x3F99ECA5
                           0x3F9394DD
                           0x3F8DF39D
                           0x3F88EDCA
                           0x3F846C9F
                           0x3F805DCC
                           0x3F7BBC4C
                           0x3F75119F
                           0x3F6EFDED
                           0x3F696F81
                           0x3F64571F
                           0x3F5FA7F1
                           0x3F5B55E3
                           0x3F575811
                           0x3F53A547
                           0x3F503693
                           0x3F4D0511
                           0x3F4A0BA3
                           0x3F474490
                           0x3F44ABC4
                           0x3F423D79
                           0x3F3FF61D
                           0x3F3DD182
                           0x3F39F466
                           0x3F362A0D
                           0x3F329714
                           0x3F2F37EB
                           0x3F2C08B2
                           0x3F2905A5
                           0x3F262BC8
                           0x3F2378DC
                           0x3F20E9AC
                           0x3F1E7BDA
                           0x3F1C2DCC
                           0x3F19FCE1
                           0x3F17E780
                           0x3F15EC3A
                           0x3F140949
                           0x3F123D5A
                           0x3F10874B
                           0x3F0EE537
                           0x3F0D56BC
                           0x3F0BDA49
                           0x3F0A6F81
                           0x3F0914B5
                           0x3F07C97A
                           0x3F068D79
                           0x3F055F8C
                           0x3F043E66
                           0x3F032A68
                           0x3F022270
                           0x3F012612
                           0x3F0034DD
                           0x3EFF4E36
                           0x3EFE71C0
                           0x3EFD9650
                           0x3EFC03AA
                           0x3EFA82D5
                           0x3EF912DE
                           0x3EF7B3E2
                           0x3EF664BA
                           0x3EF5243A
                           0x3EF3F410
                           0x3EF2D158
                           0x3EF1BC49
                           0x3EF0B3DA
                           0x3EEFBAA6
                           0x3EEECC7A
                           0x3EEDEB4D
                           0x3EED15D1
                           0x3EEC4B11
                           0x3EEB8BA4
                           0x3EEAD82C
                           0x3EEA2F3F
                           0x3EE98FEE
                           0x3EE8FB66
                           0x3EE870B5
                           0x3EE7EF2E
                           0x3EE778CA
                           0x3EE70A1D
                           0x3EE6A6A4
                           0x3EE64BA0
                           0x3EE5F961
                           0x3EE5AFFA
                           0x3EE56FCA
                           0x3EE538E1
                           0x3EE5091F
                           0x3EE4E376
                           0x3EE4C54A
                           0x3EE4B06E
                           0x3EE4A31F
                           0xBEEDBA27
                           0x3EEDBA2A
                           0xBEED5229
                           0x3EE790FE
                           0xBEECEF97
                           0x3EE19460
                           0xBEEC9204
                           0x3EDBC331
                           0xBEEC3926
                           0x3ED619AA
                           0xBEEBE474
                           0x3ED095D7
                           0xBEEB93D4
                           0x3ECB36E2
                           0xBEEB47B2
                           0x3EC5F888
                           0xBEEAFEB0
                           0x3EC0DAE2
                           0xBEEAB92E
                           0x3EBBDC3E
                           0xBEEA76D8
                           0x3EB6FA9E
                           0xBEEA37E5
                           0x3EB23455
                           0xBEE9FB52
                           0x3EAD89AF
                           0xBEE9C220
                           0x3EA8F5D3
                           0xBEE98B11
                           0x3EA47B41
                           0xBEE95689
                           0x3EA01684
                           0xBEE924AC
                           0x3E9BC811
                           0xBEE8F47E
                           0x3E978DA8
                           0xBEE8C650
                           0x3E93670E
                           0xBEE89ACA
                           0x3E8F53B4
                           0xBEE87160
                           0x3E8B51FE
                           0xBEE848B2
                           0x3E8760F2
                           0xBEE82267
                           0x3E8380A0
                           0xBEE7FDA0
                           0x3E7F5F30
                           0xBEE7DA47
                           0x3E77DB68
                           0xBEE7B8C6
                           0x3E707356
                           0xBEE79890
                           0x3E692694
                           0xBEE779D3
                           0x3E61F3AA
                           0xBEE75C31
                           0x3E5AD9DC
                           0xBEE7403F
                           0x3E53D746
                           0xBEE72573
                           0x3E4CEB18
                           0xBEE70B5E
                           0x3E4614C8
                           0xBEE6F2E8
                           0x3E3F52F0
                           0xBEE6DB73
                           0x3E38A47C
                           0xBEE6C45E
                           0x3E320828
                           0xBEE6AFAE
                           0x3E2B7F3C
                           0xBEE69B3D
                           0x3E25060C
                           0xBEE68782
                           0x3E1E9D44
                           0xBEE67416
                           0x3E184268
                           0xBEE6638F
                           0x3E11F940
                           0xBEE6527C
                           0x3E0BBC20
                           0xBEE6430F
                           0x3E058CA0
                           0xBEE63456
                           0x3DFED250
                           0xBEE62580
                           0x3DF2A320
                           0xBEE6178C
                           0x3DE68A20
                           0xBEE60B70
                           0x3DDA86C0
                           0xBEE5FFC0
                           0x3DCE9A00
                           0xBEE5F42A
                           0x3DC2BA80
                           0xBEE5E9D9
                           0x3DB6ED90
                           0xBEE5DFF7
                           0x3DAB327D
                           0xBEE5D622
                           0x3D9F84B8
                           0xBEE5CE8C
                           0x3D93E760
                           0xBEE5C580
                           0x3D885C00
                           0xBEE5BFA4
                           0x3D79A1C0
                           0xBEE5B976
                           0x3D62A9A0
                           0xBEE5B389
                           0x3D4BC970
                           0xBEE5AE28
                           0x3D34F8F0
                           0xBEE5A9D1
                           0x3D1E3800
                           0xBEE5A680
                           0x3D079800
                           0xBEE5A272
                           0x3CE1BA80
                           0xBEE5A075
                           0x3CB483A0
                           0xBEE59DE6
                           0x3C8751C0
                           0xBEE59CCE
                           0x3C3460C0
                           0xBEE59B41
                           0x3BB45900 
                          ]
                   ]
floatfft_results = map(floatfft_results_raw) do t
  reinterpret.(Float32, t)
end
floatfft_time = [328, 2044, 4708, 9784, 20724, 44104, 74456]

##

approx_sqrt(x::Float32) = begin
  i = reinterpret(UInt32, x)
  i -= 0x4B0D2
  i -= UInt32(1)<<23
  i >>= 1
  i += UInt32(1)<<29
  reinterpret(Float32, i)
end
approx_sqrt2(x::Float32) = begin
  i = reinterpret(UInt32, x)
  i -= 0x4B0D2
  i -= UInt32(1)<<23
  i >>= 1
  i += UInt32(1)<<29
  reinterpret(Float32, i)
end

approx_sq(x::Float32) = begin
  i = reinterpret(UInt32, x)
  i <<= 1
  i -= UInt32(127<<23)
  i &= UInt32((1<<31) - 1)
  reinterpret(Float32, i)
end

x = Float32.(0:0.1:100)
lines(x, x.^2)
lines!(x, approx_sq.(x))

## Checking correctness of float FFT

using FFTW

data=make_data(256)[2] .|> Float32
true_fft = map(l->fft(data[1:l]), floatfft_testsizes)
t = Theme(
    Axis=(
      xlabel="Frequency",
      ylabel="Modulus",
      #width=800,
      #height=200,
     )
)
set_theme!(t)

colors=Makie.wong_colors()
f = Figure()
expe = nothing
res = nothing
for (i,size) ∈ enumerate(floatfft_testsizes)
  mod_fft = abs.(true_fft[i][1:end÷2])
  ax = Axis(f[(i+1)÷2,(i+1)%2+1], 
            title="Sample size : $size", 
            # limits=(nothing, nothing, 0, 1.1*Float64(maximum(mod_fft))),
  )
  expe = scatterlines!(floatfft_results[i][1:end÷2], color=colors[1])
  res = scatterlines!(mod_fft, color=colors[2], marker=:+)
end

i = length(floatfft_testsizes) + 1
Legend(f[(i+1)÷2,(i+1)%2+1], 
       [expe, res], 
       ["Arduino Float FFT", "Julia Float32 FFT"],
       tellwidth=false,
       tellheight=false
  )

# resize_to_layout!(f)
save("FloatFFT_results.png", f)
f

## Plotting time results.

positions = map([approxfft_testsizes; floatfft_testsizes]) do x
  findmin(abs.(x.-approxfft_testsizes))[2]
end
colors = Makie.wong_colors()
fig = Figure()
ax = Axis(fig[1,1],
          title="ApproxFFT vs FloatFFT execution time.",
          xticks=(1:length(approxfft_testsizes), string.(approxfft_testsizes, base=10)),
          xlabel="Array size",
          ylabel="Execution time (ms)"
         )

times = Float32[approxfft_time; floatfft_time]./1000
barplot!(
         ax,
         positions,
         times,
         bar_labels= times,
         dodge=[repeat([1],length(approxfft_testsizes)); repeat([2],length(floatfft_testsizes))],
         color=colors[[repeat([1],length(approxfft_testsizes)); repeat([2],length(floatfft_testsizes))]],
        )
labels = ["ApproxFFT", "FloatFFT"]
elements = [PolyElement(polycolor = colors[i]) for i in 1:length(labels)]
title = "Implementation"

Legend(fig[1,2], elements, labels, title)
save("execution_time_comparison.png", fig)
fig

##


result = zeros(UInt8, 4)
LibSerialPort.open(portname, baudrate) do sp
  read!(sp, result)
end
