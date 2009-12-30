#!/bin/bash
# script to set up individual rendering server

LogFile=log

ERROR()
{
  echo error: $*
  exit 1
}

USAGE()
{
  [ -z "$1" ] || echo error: $*
  echo usage: $(basename "$0") '<options>' command
  echo '       --help         -h         this message'
  echo '       --verbose      -v         more messages'
  echo '       --get-index=n  -g <n>     where to rsync the pickles from [1 => render1]'
  echo '       --index-only   -i         only do the index'
  echo '       --no-run       -n         do not run final make'
  echo '       --sequential   -s         run rendering in series'
  echo '       --clear        -c         clear work and dest dirs'
  echo '       --re-parse     -r         clear parse and render stamps'
  echo '       --language=xx  -l         set language [en]'
  echo '       --work=dir     -w <dir>   workdir [work]'
  echo '       --dest=dir     -d <dir>   destdir [image]'
  exit 1
}


verbose=no
index=
clear=no
work=work
dest=image
run=yes
seq=no
IndexOnly=no
debug=
language=en

getopt=/usr/local/bin/getopt
[ -x "${getopt}" ] || getopt=getopt
args=$(${getopt} -o hvg:p:inscrl:w:d: --long=help,verbose,get-index:,index-only,no-run,sequential,clear,re-parse,language:,work:,dest:,debug -- "$@") ||exit 1

# replace the arguments with the parsed values
eval set -- "${args}"

while :
do
  case "$1" in
    -v|--verbose)
      verbose=yes
      shift
      ;;

    -g|--get-index)
      index=$2
      shift 2
      ;;

    -i|--index-only)
      IndexOnly=yes
      shift
      ;;

    -n|--no-run)
      run=no
      shift
      ;;

    -s|--sequential)
      seq=yes
      shift
      ;;

    -c|--clear)
      clear=yes
      shift
      ;;

    -r|--re-parse)
      rm -f stamp-r-parse*
      rm -f stamp-r-render*
      clear=no
      shift
      ;;

    -l|--language)
      language=$2
      shift 2
      ;;

    -w|--work)
      work=$2
      shift 2
      ;;

    -d|--dest)
      dest=$2
      shift 2
      ;;

    --debug)
      debug=echo
      shift
      ;;

    --)
      shift
      break
      ;;

    -h|--help)
      USAGE
      ;;

    *)
      USAGE invalid option: $1
      ;;
  esac
done


[ -z "${language}" ] && USAGE language is not set

work="${work}/${language}"
dest="${dest}/${language}"
license="${licenses}/${language}/license.xml"
terms="${licenses}/${language}/license.xml"
articles_link="${language}wiki-pages-articles.xml"
articles=$(readlink -m "${articles_link}")

[ -f "${articles}" ] || USAGE error articles link: ${articles_link} not set correctly

[ -f "${license}" ] || license="${licenses}/en/license.xml"
[ -f "${terms}" ] || terms="${licenses}/en/terms.xml"

xml="${license} ${terms} ${articles}"

# extract numeric suffix from host name
# expect that the rendering hosts are numbered from zero
this_host=$(hostname --short)
this_id=${this_host##*[^0-9]}
[ -z "${this_id}" ] && this_id=0

farm="farm${this_id}"

rm -f "${LogFile}"

# clean up
case "${clear}" in
  [yY]|[yY][eE][sS])
    eval ${debug} "time make clean-index DESTDIR='${dest}' WORKDIR='${work}' XML_FILES='${xml}'"
    eval ${debug} "time make '${farm}-clean' DESTDIR='${dest}' WORKDIR='${work}' XML_FILES='${xml}'"
    eval ${debug} "rm -rf '${work}' '${dest}'"
    ;;
esac

# create directories
eval ${debug} "mkdir -p '${work}'"
eval ${debug} "mkdir -p '${dest}'"

# update
git pull --rebase

# copy the index from another machine
if [ -n "${index}" ]
then
  list='articles.db offsets.db counts.text'
  items=
  for i in ${list}
  do
    items="${items} ${host}${index}:samo/${work}/${i}"
  done
  eval ${debug} "rsync -avHx --progress ${items} '${work}'/"
  eval ${debug} "touch stamp-r-index"
fi

# run the build
case "${run}" in
  [yY]|[yY][eE][sS])

    eval ${debug} "time make 'stamp-r-index' DESTDIR='${dest}' WORKDIR='${work}' XML_FILES='${xml}'" 2>&1 | tee -a "${LogFile}"

    case "${IndexOnly}" in
      [yY]|[yY][eE][sS])
        ;;
      *)
        case "${seq}" in
          [yY]|[yY][eE][sS])
            eval ${debug} "time make -j3 '${farm}-parse' DESTDIR='${dest}' WORKDIR='${work}' XML_FILES='${xml}'" 2>&1 | tee -a "${LogFile}"
            eval ${debug} "time make '${farm}-render' DESTDIR='${dest}' WORKDIR='${work}' XML_FILES='${xml}'" 2>&1 | tee -a "${LogFile}"
            ;;
          *)
            eval ${debug} "time make -j3 '${farm}' DESTDIR='${dest}' WORKDIR='${work}' XML_FILES='${xml}'" 2>&1 | tee -a "${LogFile}"
            ;;
        esac
    esac
esac
