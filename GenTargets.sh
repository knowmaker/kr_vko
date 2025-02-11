#!/bin/bash
# Version 3.1
(( BASH_VERSINFO[0] < 4 )) && exit 1

declare -A TId
MaxKolTargets=50      # Максимальное количество целей
Probability=70        # Вероятность поражения %

RangeX=13000000       # Метры
RangeY=9000000        # Метры
XYminusInt=10

types="bsr"           # типы целей
declare -A SpeedMinArray=( ["b"]=8000 ["s"]=50 ["r"]=250 )   # Скорость М/с min, 
declare -A SpeedPlusArray=( ["b"]=2000 ["s"]=199 ["r"]=750 ) # разница между максимумом и минимумом
declare -A TtlMaxArray=( ["b"]=300 ["s"]=200 ["r"]=200 )     # Максимальное время жизни
declare -A TipTargetArray=( ["b"]="Бал.блок" ["s"]="Самолет" ["r"]="К.ракета" )

Sleeptime=1           # Задержка 1с
d=0                   # Отладка
declare -A tsign_map=( ["b"]="\033[0;31m\033[7m^\033[0m\033[0m" ["s"]="\033[0;34m\033[7m>\033[0m\033[0m"  ["r"]="\033[0;32m\033[7m-\033[0m\033[0m" )
for ((i = 0; i < 5895; i++)); do  maps[$i]=" "; done
TmpDir=/tmp/GenTargets
TDir="$TmpDir/Targets"
DDir="$TmpDir/Destroy"
LogFile="$TmpDir/GenTargets.log"
clean=0
Nt=1
mkdir -p "$TmpDir" "$TDir" "$DDir" &>/dev/null
echo "Запуск в " `date` >>"$LogFile"
cd "$TDir/" || exit
find $TDir $DDir -type f -delete &>/dev/null

while :
do
  if [[ -z "${TId[${Nt}_id]}" ]]; then # Генерация цели
    tip_targetid="${types:$(($RANDOM % ${#types})):1}"
    SpeedMin=${SpeedMinArray[$tip_targetid]}
    SpeedPlus=${SpeedPlusArray[$tip_targetid]}
    ttl=$((RANDOM % TtlMaxArray[$tip_targetid] + 10))
    tip_target=${TipTargetArray[$tip_targetid]}

    RadialSpeed=$(((RANDOM % SpeedPlus) + SpeedMin + 1))
    SpeedX=$((RANDOM % (RadialSpeed + 1)))
    SpeedYSquared=$((RadialSpeed * RadialSpeed - SpeedX * SpeedX))
    SpeedY=$(echo "scale=0; sqrt($SpeedYSquared)" | bc -l)
    destX=$((RANDOM % 2));(( destX == 0 )) && SpeedX=$((-SpeedX))
    destY=$((RANDOM % 2));(( destY == 0 )) && SpeedY=$((-SpeedY))

    Speed=$(echo "scale=0; sqrt($SpeedX * $SpeedX + $SpeedY * $SpeedY)" | bc -l)
    if ((Speed < SpeedMin)); then
        factor=$(echo "scale=10; ($SpeedMin + $SpeedPlus) / (2 * $Speed)" | bc -l)
        SpeedX=$(echo "($SpeedX * $factor + 0.5) / 1" | bc -l)
        SpeedY=$(echo "($SpeedY * $factor + 0.5) / 1" | bc -l)
    elif ((Speed > SpeedMin + SpeedPlus)); then
        factor=$(echo "scale=10; $Speed / ($SpeedMin + $SpeedPlus)" | bc -l)
        SpeedX=$(echo "($SpeedX / $factor + 0.5) / 1" | bc -l)
        SpeedY=$(echo "($SpeedY / $factor + 0.5) / 1" | bc -l)
    fi
    SpeedX=$(echo "$SpeedX / 1" | bc)
    SpeedY=$(echo "$SpeedY / 1" | bc)

    if [ $destX -eq 1 ]; then
        Xmin=$(( (RangeX * XYminusInt) / 100 ))
        Xmax=$(( RangeX - (RangeX * XYminusInt / 100) - (RangeX * 30 / 100) ))
    else
        Xmin=$(( (RangeX * 30 / 100) + (RangeX * XYminusInt / 100) ))
        Xmax=$(( RangeX - (RangeX * XYminusInt / 100) ))
    fi
    if [ $destY -eq 1 ]; then
        Ymin=$(( (RangeY * XYminusInt) / 100 ))
        Ymax=$(( RangeY - (RangeY * XYminusInt / 100) - (RangeY * 30 / 100) ))
    else
        Ymin=$(( (RangeY * 30 / 100) + (RangeY * XYminusInt / 100) ))
        Ymax=$(( RangeY - (RangeY * XYminusInt / 100) ))
    fi
    Xkoord=$((RANDOM % ((Xmax - Xmin) / 1000) * 1000 + Xmin))
    Ykoord=$((RANDOM % ((Ymax - Ymin) / 1000) * 1000 + Ymin))
    TId[${Nt}_id]=$(openssl rand -hex 16 2>/dev/null | cut -c 1-6)$tip_targetid
    TId[${Nt}_tid]=$tip_targetid
    TId[${Nt}_type]=$tip_target
    TId[${Nt}_koordX]=$Xkoord
    TId[${Nt}_koordY]=$Ykoord
    TId[${Nt}_speedX]=$SpeedX
    TId[${Nt}_speedY]=$SpeedY
    TId[${Nt}_speed]=$Speed
    TId[${Nt}_ttl]=$ttl
    printf "%s: " $(date +%T) >> "$LogFile"
    printf "%-20s %8s %3d Koord X: %-11d Y: %-11d Speed:%-8d X: %-8d Y: %-8d Ttl %3d\n" \
      "${TId[${Nt}_type]}" "${TId[${Nt}_id]}" "$Nt" "${TId[${Nt}_koordX]}" "${TId[${Nt}_koordY]}" \
      "${TId[${Nt}_speed]}" "${TId[${Nt}_speedX]}" "${TId[${Nt}_speedY]}" \
      "${TId[${Nt}_ttl]}" |tee -a "$LogFile"
  else  # Обновление цели
    if [ -n "${TId[${Nt}_id]}" ] && [ -e "$DDir/${TId[${Nt}_id]}" ]; then # Уничтожение цели по запросу
      info=$(head -n1 $DDir/${TId[${Nt}_id]}  2>/dev/null)
      rm "$DDir/${TId[${Nt}_id]}"
      if (( RANDOM % 100 < Probability )); then
        printf "%s: " $(date +%T) >> "$LogFile"
        printf "\e[32m%-20s %8s %3d Koord X: %-11d Y: %-11d Speed:%-8d X: %-8d Y: %-8d \t\t%s\e[0m\n" \
          "${TId[${Nt}_type]}" "${TId[${Nt}_id]}" "$Nt" "${TId[${Nt}_koordX]}" "${TId[${Nt}_koordY]}" \
          "${TId[${Nt}_speed]}" "${TId[${Nt}_speedX]}" "${TId[${Nt}_speedY]}" "Уничтожена $info" |tee -a "$LogFile"
        TId[${Nt}_id]=''
      else
        printf "%s: " $(date +%T) >> "$LogFile"
        printf "\e[31m%-20s %8s %3d Koord X: %-11d Y: %-11d Speed:%-8d X: %-8d Y: %-8d \t\t%s\e[0m\n" \
          "${TId[${Nt}_type]}" "${TId[${Nt}_id]}" "$Nt" "${TId[${Nt}_koordX]}" "${TId[${Nt}_koordY]}" \
          "${TId[${Nt}_speed]}" "${TId[${Nt}_speedX]}" "${TId[${Nt}_speedY]}" "Промах $info" |tee -a "$LogFile"
      fi
    fi
    (( TId[${Nt}_koordX] += TId[${Nt}_speedX] ))
    (( TId[${Nt}_koordY] += TId[${Nt}_speedY] ))
    TId[${Nt}_ttl]=$(( TId[${Nt}_ttl] - 1 ))       #Уменьшение времени жизни
    h=$(echo -n "${TId[${Nt}_id]}" | xxd -p | tr -d '\n'); r=$(echo -n $(openssl rand -base64 6) | tr -d '\n' | xxd -p | head -c 16); f=$(for ((i=0; i<${#h}; i+=2)); do echo -n "${r:$i:2}${h:$i:2}"; done)
    printf "X:%10d\tY:%10d\n" ${TId[${Nt}_koordX]} ${TId[${Nt}_koordY]} > "$TDir/$f${r:(-2)}" 2>/dev/null
    ((d==1)) && printf "%s\n" ${TId[${Nt}_id]} >> "$TDir/$f${r:(-2)}" 2>/dev/null
    ((d==1)) && printf "S%10d X%10d Y%10d\n" "${TId[${Nt}_speed]}" "${TId[${Nt}_speedX]}" "${TId[${Nt}_speedY]}" >> "$TDir/$f${r:(-2)}" 2>/dev/null

    if [ "${TId[${Nt}_ttl]}" -le 0 ]; then
      printf "%s: " $(date +%T) >> "$LogFile"
      printf "\e[35m%-20s %8s %3d Koord X: %-11d Y: %-11d Speed:%-8d X: %-8d Y: %-8d %s\e[0m\n" \
        "${TId[${Nt}_type]}" "${TId[${Nt}_id]}" "$Nt" "${TId[${Nt}_koordX]}" "${TId[${Nt}_koordY]}" \
        "${TId[${Nt}_speed]}" "${TId[${Nt}_speedX]}" "${TId[${Nt}_speedY]}" "Пропала" |tee -a "$LogFile"
      TId[${Nt}_id]=''
    fi
  fi
  ((Nt+=1))
  if ((Nt > MaxKolTargets)) ; then
    Nt=1 #$MaxKolTargets
    sleep $Sleeptime
    (( clean % 10 == 0 )) && ( find $TDir -mmin +1 -type f -delete & &>/dev/null)
    if [ "$1" == "map" ] || [ "$1" == "-map" ]; then
      if (( clean % 2 == 0 )); then
        clear
        for ((i = 0; i <= $MaxKolTargets; i++)); do
          if [ ! -z "${TId[${i}_id]}" ]; then
            [[ ${TId[${i}_speedX]} -ge 0 ]] && [[ ${TId[${i}_speedY]} -ge 0 ]] && destinXY=$(echo -e '\U00002197') || \
            [[ ${TId[${i}_speedX]} -ge 0 ]] && destinXY=$(echo -e '\U00002198') || \
            [[ ${TId[${i}_speedY]} -ge 0 ]] && destinXY=$(echo -e '\U00002196') || destinXY=$(echo -e '\U00002199')     
            tsign=${tsign_map[${TId[${i}_tid]}]}
            X=$((TId[${i}_koordX]/100000))
            Y=$((TId[${i}_koordY]*44/9000000))
            maps[$((X+Y*130))]=$tsign
            info="${mapsid[$((Y*130))]} $destinXY ${TId[${i}_id]} "
            mapsid[$((Y*130))]=${info:0:128}
          fi
        done
        echo "┌$(printf '─%.0s' {1..131})┐"
        for y in {44..0..-1}; do
            echo -n "│"
            for x in {0..130}; do
                echo -ne "${maps[$(($x+$y*130))]:-}";maps[$(($x+$y*130))]=" "
            done
            echo "│${mapsid[$(($y*130))]}"; mapsid[$(($y*130)) ]=""
        done
        echo "└$(printf '─%.0s' {1..131})┘"
      fi
    fi
    ((clean++))
  fi
done