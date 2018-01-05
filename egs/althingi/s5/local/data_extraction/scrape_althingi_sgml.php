<meta charset = "utf-8" />
<?php
/*
Author: Judy Fong, Inga Rún Helgadóttir, Háskólinn í Reykjavík
Description Download audio and text from althingi.is based on input links

Running the script:
php local/data_extraction/scrape_althingi_xml_mp3.php /home/staff/inga/kaldi/egs/althingi/s5/data/althingiUploads/thing132_sgml.txt &
*/
set_time_limit(0);// allows infinite time execution of the php script itself
$ifile = $argv[1]; 
if ($file_handle = fopen($ifile, "r")) {
    while(!feof($file_handle)) {
        $line = fgets($file_handle);
        
        # Split the line on tabs
        list($rad,$name,$text) = preg_split('/\t+/', $line);
        $text = str_replace("\n", '', $text);
        //$rad=basename($text, ".xml");

	    // Extract the text
	    $ch = curl_init($text);
	    $text_file_name = '/data/althingi/text_corpus/AlthingiUploads/' . $rad . '.sgml';
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT ,0); 
        curl_setopt($ch, CURLOPT_TIMEOUT, 500);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 1);
        //curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 1);
	    curl_setopt($ch, CURLOPT_USERAGENT, 'HR_Althingi');
	    $output = curl_exec($ch);
	    if(curl_exec($ch) == false)
        {
            echo 'rad: ' . $rad . ' Curl error: ' . curl_error($ch) . "\n";
        }
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($status == 200) {
            file_put_contents($text_file_name, $output);
        }
        else
        {
	        echo 'rad: ' . $rad . 'Status is what?! ' . $status . ' The output is a failure ' . $output . "\n";
        }	
    }
    fclose($file_handle);
}
?>