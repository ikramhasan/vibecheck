enum RemoteScript {
    static let transcriptWindow = TranscriptFile.initialWindow
    static let headLimit = 512 * 1024
    static let serverScanTicks = 5

    static let source = #"""
    export LC_ALL=C
    shopt -s nullglob
    if [[ ! -r /proc/self/stat ]] || ! stat -c %s /proc/self/stat >/dev/null 2>&1; then
      printf 'E unsupported\n'
      exit 0
    fi
    declare -A registry=() process=() link=() listen=() loopback=() follow=() offset=() facts=() factstart=()
    sha='^[0-9a-f]{40,64}$'
    us=$'\x1f'
    gs=$'\x1d'
    tick=0
    serverfacts=""
    ticks=$(getconf CLK_TCK)
    while read -r name value _; do [[ $name == btime ]] && boot=$value; done < /proc/stat
    roots=("$HOME/.claude/projects/" "$HOME/.codex/sessions/" "$HOME/.pi/agent/sessions/")
    pifiles=""

    frame() {
      printf '%s %d\n%s' "$1" "${#2}" "$2"
    }
    reply() {
      printf 'R %s %d %d\n%s' "$1" "$2" "${#3}" "$3"
    }
    allowed() {
      local root
      [[ $1 == *.jsonl && /$1/ != */../* ]] || return 1
      for root in "${roots[@]}"; do [[ $1 == "$root"* ]] && return 0; done
      return 1
    }
    listening() {
      local table sl address remote st inode header
      listen=()
      loopback=()
      for table in /proc/net/tcp /proc/net/tcp6; do
        header=1
        while read -r sl address remote st _ _ _ _ _ inode _; do
          if (( header )); then header=0; continue; fi
          [[ $st == 0A ]] || continue
          listen[$inode]=$((16#${address##*:}))
          [[ ${address%%:*} == ??????7F || ${address%%:*} == 00000000000000000000000001000000 ]] && loopback[$inode]=1
        done < "$table"
      done
    }
    servers() {
      local path link pid inode port current stat fields start entry session body=""
      local -A owned=() wanted=()
      listening
      while read -r path link; do
        pid=${path#/proc/}
        pid=${pid%%/*}
        inode=${link//[^0-9]/}
        port=${listen[$inode]-}
        [[ -n $port ]] && owned[$pid]+="${loopback[$inode]:+l}$port "
      done < <(find /proc/[0-9]*/fd -lname 'socket:*' -printf '%p %l\n' 2>/dev/null)
      for pid in "${!owned[@]}"; do
        current=$pid
        while (( current > 1 )) && [[ -z ${wanted[$current]+x} ]]; do
          wanted[$current]=1
          read -r stat 2>/dev/null < "/proc/$current/stat" || break
          read -r -a fields <<< "${stat##*) }"
          current=${fields[1]}
        done
      done
      for pid in "${!facts[@]}"; do
        [[ -n ${wanted[$pid]+x} ]] || unset 'facts[$pid]' 'factstart[$pid]'
      done
      for pid in "${!wanted[@]}"; do
        read -r stat 2>/dev/null < "/proc/$pid/stat" || continue
        read -r -a fields <<< "${stat##*) }"
        start=$(( boot + fields[19] / ticks ))
        if [[ ${factstart[$pid]-} != "$start" ]]; then
          mapfile -d '' -t args 2>/dev/null < "/proc/$pid/cmdline"
          printf -v joined "%s$gs" "${args[@]}"
          session=""
          mapfile -d '' -t environ 2>/dev/null < "/proc/$pid/environ"
          for entry in "${environ[@]}"; do [[ $entry == CLAUDE_CODE_SESSION_ID=* ]] && session=${entry#*=}; done
          facts[$pid]="$(readlink "/proc/$pid/exe")$us$(readlink "/proc/$pid/cwd")$us${joined//$'\n'/ }$us$session"
          factstart[$pid]=$start
        fi
        body+="$pid$us${fields[1]}$us$start$us${owned[$pid]-}$us${facts[$pid]}"$'\n'
      done
      [[ $body == "$serverfacts" ]] && return
      serverfacts=$body
      frame "N" "$body"
    }
    jumpfacts() {
      local pid=$1 current=$1 depth=0 ssh="" ports=() entry stat fields environ
      while (( current > 1 && depth < 32 )); do
        if [[ -z $ssh && -r /proc/$current/environ ]]; then
          mapfile -d '' -t environ 2>/dev/null < "/proc/$current/environ"
          for entry in "${environ[@]}"; do [[ $entry == SSH_CONNECTION=* ]] && ssh=${entry#SSH_CONNECTION=}; done
        fi
        while read -r entry; do
          entry=${entry//[^0-9]/}
          [[ -n ${listen[$entry]-} ]] && ports+=("${listen[$entry]}")
        done < <(find "/proc/$current/fd" -lname 'socket:*' -printf '%l\n' 2>/dev/null)
        read -r stat 2>/dev/null < "/proc/$current/stat" || break
        read -r -a fields <<< "${stat##*) }"
        current=${fields[1]}
        (( depth++ ))
      done
      link[$pid]="ssh=$ssh"$'\n'"ports=${ports[*]}"
    }
    query() {
      local id=$1 op=$2 dir=$3 arg=$4 output
      [[ $id =~ ^[0-9]+$ ]] || return
      if [[ $dir != /* || ! -d $dir ]]; then reply "$id" 255 ""; return; fi
      local git=(git -C "$dir" -c core.quotepath=off --no-pager)
      case $op in
        toplevel) set -- "${git[@]}" rev-parse --show-toplevel ;;
        branch) set -- "${git[@]}" symbolic-ref -q --short HEAD ;;
        head) set -- "${git[@]}" rev-parse -q --verify 'HEAD^{commit}' ;;
        reflog) [[ $arg =~ ^[0-9]+$ ]] || { reply "$id" 255 ""; return; }
          set -- "${git[@]}" rev-parse -q --verify "HEAD@{@$arg}^{commit}" ;;
        before) [[ $arg =~ ^[0-9]+$ ]] || { reply "$id" 255 ""; return; }
          set -- "${git[@]}" rev-list -1 "--before=$arg" HEAD ;;
        numstat) [[ $arg =~ $sha ]] || { reply "$id" 255 ""; return; }
          set -- "${git[@]}" diff --numstat -z "$arg" -- ;;
        untracked) set -- "${git[@]}" ls-files --others --exclude-standard -z ;;
        ancestor) [[ $arg =~ $sha ]] || { reply "$id" 255 ""; return; }
          set -- "${git[@]}" merge-base --is-ancestor "$arg" HEAD ;;
        patch) [[ $arg =~ $sha ]] || { reply "$id" 255 ""; return; }
          set -- "${git[@]}" diff -M --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ "$arg" -- ;;
        file) if [[ -n $arg && $arg != /* && /$arg/ != */../* && -f $dir/$arg ]] \
              && (( $(stat -c %s -- "$dir/$arg") <= \#(GitDiffStats.largestCountedFile) )); then
            set -- cat -- "$dir/$arg"
          else
            reply "$id" 1 ""
            return
          fi ;;
        *) reply "$id" 255 ""; return ;;
      esac
      output=$(set -o pipefail; GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 timeout 10 "$@" 2>/dev/null | base64 -w0)
      reply "$id" "$?" "$output"
    }

    frame "V 2" "$HOME"
    while :; do
      IFS=$'\t' read -r -t 1 -a request
      status=$?
      if (( status == 0 )); then
        key=${request[1]-}
        case ${request[0]-} in
          F) if [[ $key =~ ^[A-Za-z0-9._-]+$ ]] && allowed "${request[2]-}"; then
              follow[$key]=${request[2]}
              unset 'offset[$key]'
            fi ;;
          U) unset 'follow[$key]' 'offset[$key]' ;;
          Q) query "$key" "${request[2]-}" "${request[3]-}" "${request[4]-}" ;;
        esac
      elif (( status <= 128 )); then
        exit 0
      fi

      declare -A alive=()
      for file in "$HOME"/.claude/sessions/*.json; do
        key=${file##*/}
        key=${key%.json}
        [[ $key =~ ^[0-9]+$ && -d /proc/$key ]] || continue
        alive[$key]=1
        data=$(<"$file") || continue
        [[ ${registry[$key]-} == "$data" ]] && continue
        registry[$key]=$data
        frame "S $key" "$data"
      done
      for key in "${!registry[@]}"; do
        [[ -n ${alive[$key]-} ]] && continue
        unset 'registry[$key]'
        printf 'G %s\n' "$key"
      done

      declare -A candidate=()
      oldest=""
      for dir in /proc/[0-9]*; do
        pid=${dir#/proc/}
        [[ -O $dir ]] || continue
        read -r comm 2>/dev/null < "$dir/comm" || continue
        if [[ $comm != codex && $comm != node* && $comm != pi && -z ${registry[$pid]+x} ]]; then continue; fi
        mapfile -d '' -t args 2>/dev/null < "$dir/cmdline" || continue
        if [[ $comm == node* || $comm == pi ]] && [[ -z ${registry[$pid]+x} ]]; then
          [[ ${args[0]-} == pi || ${args[1]-} == *pi-coding-agent* || ${args[1]##*/} == pi ]] || continue
        fi
        candidate[$pid]=$comm
      done
      for pid in "${!candidate[@]}"; do
        if [[ -z ${link[$pid]+x} ]]; then listening; break; fi
      done
      for pid in "${!candidate[@]}"; do
        dir=/proc/$pid
        comm=${candidate[$pid]}
        read -r stat 2>/dev/null < "$dir/stat" || continue
        read -r -a fields <<< "${stat##*) }"
        start=$(( boot + fields[19] / ticks ))
        mapfile -d '' -t args 2>/dev/null < "$dir/cmdline"
        printf -v joined "%s$us" "${args[@]}"
        environment=""
        mapfile -d '' -t environ 2>/dev/null < "$dir/environ"
        for entry in "${environ[@]}"; do [[ $entry == PI_SUBAGENT_CHILD=* ]] && environment=$entry; done
        files=""
        if [[ $comm == codex ]]; then
          files=$(find "$dir/fd" -lname "$HOME/.codex/sessions/*.jsonl" -printf "%l$us" 2>/dev/null)
        fi
        if [[ $comm == node* || $comm == pi ]] && [[ -z $oldest || $start -lt $oldest ]]; then oldest=$start; fi
        [[ -n ${link[$pid]+x} ]] || jumpfacts "$pid"
        body="comm=$comm"$'\n'"start=$start"$'\n'"cwd=$(readlink "$dir/cwd")"$'\n'"args=${joined//$'\n'/ }"
        body+=$'\n'"env=$environment"$'\n'"files=$files"$'\n'"${link[$pid]}"
        [[ ${process[$pid]-} == "$body" ]] && continue
        process[$pid]=$body
        frame "P $pid" "$body"
      done
      for pid in "${!process[@]}"; do
        [[ -n ${candidate[$pid]-} ]] && continue
        unset 'process[$pid]' 'link[$pid]'
        printf 'X %s\n' "$pid"
      done
      listing=""
      if [[ -n $oldest && -d $HOME/.pi/agent/sessions ]]; then
        listing=$(find "$HOME/.pi/agent/sessions" -name '*.jsonl' -newermt "@$((oldest - 5))" -printf '%T@ %p\n' 2>/dev/null)
      fi
      if [[ $listing != "$pifiles" ]]; then
        pifiles=$listing
        frame "L" "$listing"
      fi

      (( tick++ % \#(serverScanTicks) == 0 )) && servers

      for key in "${!follow[@]}"; do
        file=${follow[$key]}
        stamp=$(stat -c '%s %Y' -- "$file" 2>/dev/null) || continue
        size=${stamp% *}
        start=${offset[$key]-}
        if [[ -z $start && $file == "$HOME/.codex/sessions/"* ]]; then
          frame "H $key" "$(head -n 1 -- "$file" | head -c \#(headLimit))"
        fi
        if [[ -z $start ]] || (( size < start )); then
          if (( size > \#(transcriptWindow) )); then
            start=$((size - \#(transcriptWindow)))
            mode=tail
          else
            start=0
            mode=start
          fi
        elif (( size == start )); then
          continue
        else
          mode=more
        fi
        printf 'T %s %s %d %s\n' "$key" "$mode" "$((size - start))" "${stamp#* }"
        tail -c "+$((start + 1))" -- "$file" | head -c "$((size - start))"
        offset[$key]=$size
      done
    done

    """#
}
