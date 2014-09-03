BEGIN {
  lastcategory = "";
  tmpl = "\t\t<li><a href=\"%s-index.html\">%s</a></li>\n"
}

{
  print $2
  if ($1 != lastcategory) {

    printf(tmpl,$1,$1) > scriptdir"/static/gallery-catnav-contrib.html"
    lastcategory = $1
  }
}

END {}
