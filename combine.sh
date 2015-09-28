#!/bin/bash 

# combine student attachment submission from Collab into one PDF file for print
# Takes one parameter：the bulk_download.zip from Collab
#
# Usage: bash combine.sh /path/to/bulk_download.zip
#
# for MS Word file conversion, requires pyodconverter-master under the same 
# directory of this script


# some constants or configurations
# add more image file extension names if you need
allowed_img_files=("jpg", "jpeg", "png", "PNG", "xcf", "tiff", "JPG")
allowed_doc_files=("doc", "docx")
tmp_suf="prnttmp" # just a suffix for temporary pdf file

# path the bulk file
bulk_file_path=$1
bulk_file_name=$(basename $1)

# current directory
cur_dir=`pwd`

# generate a random value for as temporary working dir path
temp_path="/tmp/combCollab$RANDOM/"
mkdir $temp_path
echo "Temporary working dir is $temp_path"

# mkdir temporary output dir
output_dir="$temp_path/pdfs/"
mkdir $output_dir

# copy bulk_download.zip to temp working dir
cp $1 $temp_path
cd $temp_path
unzip $bulk_file_name >log.txt

# start a LibreOffice instance for converting MS Word file to pdf
soffice --headless --accept="socket,host=127.0.0.1,port=2002;urp;" --nofirststartwizard &
office_pid=$!
echo "LibreOffice (pid $office_pid) created"

#find all the submission dir
dirs=()
while IFS= read -r -d $'\n' dir; do
  dirs+=("$dir")
done < <(find . -type d -name "Submission attachment(s)")


total_combined=0
for dir in "${dirs[@]}"
do
    #get the student's name
    name=`echo $dir | sed 's/.*\/\(.*\)\/Submission attachment(s)$/\1/g'`
    pdf_name="$name.pdf"
    # remove previous cover pages
    rm "$dir/cover.$tmp_suf.ps" 2> /dev/null
    rm "$dir/cover.$tmp_suf.pdf" 2> /dev/null
    rm "$dir/cover.$tmp_suf.ps~" 2> /dev/null

    # find all submission files
    files=()
    while IFS= read -r -d $'\n' file; do
	files+=("$file")
    done < <(find "$dir" -type f)

    # if no submission the goto next person
    if [ ${#files[@]} = 0 ]
    then
	continue
    fi
    echo "Processing $name..."

    # process the submission files
    error=0
    sub_files=()
    for file in "${files[@]}"
    do
	# get extentsion name from file
	ext_name=`echo $file | sed 's/.*\.\(.*\)$/\1/g'`
	# if this is already pdf file, then just add it to submitted
	# file list
	if [ $ext_name = "pdf" ]
	then
	    sub_files+=("$file")
	    continue # proceed to next file
	fi
	# if this a txt file convert it to pdf
	if [ $ext_name = "txt" ]
	then
	    enscript "$file" --output=- | ps2pdf - "$file.$tmp_suf.pdf"
	    sub_files+=("$file.$tmp_suf.pdf")
	    continue # proceed to next file
	fi
	
	# if this is a image file, covert it to pdf, the add to the 
        # submitted file list
	if [[ ${allowed_img_files[*]} =~ "$ext_name" ]]
	then
	    convert -page Letter "$file" "$file.$tmp_suf.pdf"
	    sub_files+=("$file.$tmp_suf.pdf")
	    continue # proceed to next file
	elif [[ ${allowed_doc_files[*]} =~ "$ext_name" ]]
	then
	    python3 $cur_dir/pyodconverter-master/DocumentConverter.py "$file" "$file.$tmp_suf.pdf"
	    sub_files+=("$file.$tmp_suf.pdf")
            continue # proceed to nex file
	else
	    error=1
	    echo "Unknown file type: $file" 
	    break
	fi
    done
    
    if [ $error == 1 ]
    then
	continue # proceed to next person
    fi

    #create a cover page pdf and add to submitted file list
    echo $name | a2ps -q -1 -B --portrait --borders=no --font-size=20 -o "$dir/cover.$tmp_suf.ps"
    ps2pdf "$dir/cover.$tmp_suf.ps" "$dir/cover.$tmp_suf.pdf"

    sub_files=("$dir/cover.$tmp_suf.pdf" "${sub_files[@]}")

    #echo "Combining files:" $sub_files

    gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$output_dir/$pdf_name" "${sub_files[@]}"
    
    rm "$dir"/*$tmp_suf*
    
    total_combined=$((total_combined + 1))
done

# combine pdfs in the $output_dir
cd $output_dir
gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=print.pdf *.pdf

# copy the temporary file out
cp print.pdf $cur_dir/combined.pdf
echo "$total_combined submissions combined"


# stop LibreOffice process
kill -TERM $office_pid

# remove temporary directory
rm -rf $temp_path
