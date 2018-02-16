#!/usr/bin/env python3

import perfection

countries = "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ " \
           +"BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ " \
           +"CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ " \
           +"DE DJ DK DM DO DZ EC EE EG ER ES ET FI FJ FK FM FO FR " \
           +"GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY " \
           +"HK HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP " \
           +"KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY " \
           +"MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ " \
           +"NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY " \
           +"QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ " \
           +"TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ " \
           +"VA VC VE VG VI VN VU WF WS XK YE YT ZA ZM ZW ZZ"

countries = countries.lower()
c_list  = countries.split(" ")

# Chain country double chars together
markov  = dict()
for c in c_list:
    c1,c2 = c[0],c[1]
    markov.setdefault(c1,set()).add(c2)

c_string = ""
c_map    = dict()
c_codes  = []
last_ch  = None
while markov:
    if last_ch and last_ch in markov: # Have candidate for follower
        candidates = list(markov[last_ch])
        candidates.sort(key=lambda ch:len(markov.get(ch,'')))
        best_ch = candidates.pop()
        markov[last_ch].discard(best_ch)
        if len(markov[last_ch]) == 0:
            markov.pop(last_ch)
        c_string += best_ch
        last_ch = best_ch
        cn = c_string[-2:]
        c = (ord(cn[0])<<8) + ord(cn[1])
        c_map[c] = len(c_string)-2
        if len(c_string)-2 != len(c_codes):
            c_codes.append(0)
        c_codes.append(c)
    else:
        candidates = list(markov)
        candidates.sort(key=lambda ch:len(markov.get(ch,'')))
        best_ch = candidates.pop()
        c_string += best_ch
        last_ch = best_ch

params = perfection.hash_parameters(c_codes)

t = params.t
r = params.r
offset = params.offset

def perfect_hash(x):
    val = x + offset
    x = val % t
    y = val // t
    return c_map[params.slots[x + r[y]]]

for cn in c_list:
    c = (ord(cn[0])<<8) + ord(cn[1])
    h = perfect_hash(c)
    cnx = c_string[h:h+2]
    assert(cn == cnx)

assert(255 not in params.r)
assert(255 not in params.slots)

print('t=',params.t)
print('offset=',params.offset)
print('r=',[(x if x else 255) for x in params.r])
print('slots_i=',[c_map.get(c,255) for c in params.slots])
print('c_string=',c_string)
print('len(c_string)=',len(c_string))