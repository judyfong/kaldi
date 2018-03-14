<meta charset = "utf-8" />
<?php
/*
Author: Judy Fong, Inga Rún Helgadóttir, Háskólinn í Reykjavík
Description Download audio and text from althingi.is based on input links

Running the script:
php local/data_extraction/scrape_althingi_xml_mp3.php /data/althingi/corpus_okt2017/AlthingiUploads/thing132_mp3_xml.txt &
*/
set_time_limit(0);// allows infinite time execution of the php script itself
$ifile = $argv[1]; 
if ($file_handle = fopen($ifile, "r")) {
    while(!feof($file_handle)) {
        $line = fgets($file_handle);
        
        // Split the line on tabs
        list($rad,$name,$mp3,$text) = preg_split('/\t+/', $line);
        $text = str_replace("\n", '', $text);
        //$rad=basename($text, ".xml");

	    // Extract the text
	    $ch = curl_init($text);
	    $text_file_name = '/data/althingi/corpus_Des2016-March2018/text_endanlegt/' . $rad . '.xml';
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT ,0); 
        curl_setopt($ch, CURLOPT_TIMEOUT, 600);
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
            echo 'Text: rad: ' . $rad . "\n";
	        echo 'status is what?! ' . $status . "\n";
	        echo 'the output is a failure ' . $output . "\n";
	    }	
    }
    fclose($file_handle);
}
?>