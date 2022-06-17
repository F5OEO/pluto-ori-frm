plutorx -s 240e3 -f 107.7e6 | csdr convert_s16_f | csdr fmdemod_quadri_cf | csdr fractional_decimator_ff 5 | csdr deemphasis_wfm_ff 48000 50e-6 | csdr convert_f_s16 | aplay -f S16_LE -c 1 -r 48000

