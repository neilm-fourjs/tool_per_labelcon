# Program to generate a .per from a 42f and convert static labels to dynamic.
IMPORT os
&include "labelconv.inc"

DEFINE g_titl STRING
DEFINE m_scr DYNAMIC ARRAY OF CHAR(200)
DEFINE m_fields DYNAMIC ARRAY OF RECORD
	id CHAR(5),
	ty CHAR(20),
	tb CHAR(18),
	nm CHAR(18),
	ar CHAR(350)
END RECORD
DEFINE fields SMALLINT
DEFINE max_scr SMALLINT
DEFINE l, scr_x, scr_y SMALLINT
DEFINE single, double1, double2 SMALLINT
DEFINE dbname STRING

DEFINE m_tabs DYNAMIC ARRAY OF CHAR(28)
DEFINE no_of_tabs SMALLINT

DEFINE key DYNAMIC ARRAY OF CHAR(20)
DEFINE key_name DYNAMIC ARRAY OF CHAR(50)
DEFINE no_of_keys SMALLINT

DEFINE chan base.Channel
DEFINE per base.Channel

DEFINE actions om.DomNode

DEFINE chase_ky SMALLINT
DEFINE ver STRING

DEFINE conv_labs, ignore_genero_forms SMALLINT
DEFINE labno SMALLINT
DEFINE labtxt DYNAMIC ARRAY OF STRING
DEFINE labattr DYNAMIC ARRAY OF STRING
MAIN
	DEFINE fname STRING
	DEFINE x SMALLINT
	DEFINE k_doc om.DomDocument
	DEFINE k_node om.DomNode
	DEFINE key_node om.DomNode

	LET no_of_keys = 1

	LET conv_labs = TRUE
	LET ignore_genero_forms = FALSE
	LET ver = "$Id$" -- If NULL then TIMESTAMP is used.

	DISPLAY copyright, " ", version

	LET fname = ARG_VAL(1)
	LET dbname = ARG_VAL(2)
	IF ARG_VAL(3) = "N" THEN
		LET conv_labs = FALSE
	END IF

	DISPLAY "Database:", dbname

	IF fname = "ALL" THEN
		CALL prog_all()
	ELSE
		CALL prog_form(fname)
	END IF

	LET k_doc = om.DomDocument.create("DefaultActions")
	LET k_node = k_doc.getDocumentElement()
--		DISPLAY "Keys:"
	FOR x = 1 TO no_of_keys
		IF key[x] IS NOT NULL AND key[x] != " " THEN
			LET key_node = k_node.createChild("Action")
			CALL key_node.setAttribute("acceleratorName", key[x] CLIPPED)
			CALL key_node.setAttribute("name", key[x] CLIPPED)
			CALL key_node.setAttribute("text", key_name[x] CLIPPED)
			--			DISPLAY key[x]," ",key_name[x]
		END IF
	END FOR
	CALL k_node.writeXML("keys.xml")

	DISPLAY "Finished."

END MAIN
--------------------------------------------------------------------------------
FUNCTION prog_all()
	DEFINE l_buffer STRING
	DEFINE ch base.Channel

	DISPLAY "Opening Pipe..."
	LET ch = base.Channel.create()

	CALL ch.openPipe("ls -1 *.42f", "r")
	IF STATUS != 0 THEN
		DISPLAY "Error with open pipe:", STATUS
		EXIT PROGRAM
	END IF
	DISPLAY "Reading from pipe..."
	WHILE ch.read(l_buffer)
		DISPLAY l_buffer.trim()
		CALL prog_form(l_buffer.trim())
	END WHILE
	CALL ch.close()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION prog_form(l_fname STRING) RETURNS()
	DEFINE f_doc om.DomDocument
	DEFINE f_node om.DomNode
	DEFINE l_outname, l_bakname STRING
	DEFINE nl om.nodeList
	DEFINE x SMALLINT

	LET fields = 0
	LET single = 0
	LET double1 = 0
	LET double2 = 1
	LET no_of_tabs = 0
	LET max_scr = 0
	LET chase_ky = 0

	LET chan = base.Channel.create()
	CALL m_scr.clear()
	CALL m_fields.clear()
	CALL m_tabs.clear()

	DISPLAY "Reading ", l_fname.trim(), " ..."
	LET f_doc = om.DomDocument.createFromXmlFile(l_fname)
	IF f_doc IS NULL THEN
		DISPLAY "Failed to open:", l_fname
		EXIT PROGRAM
	END IF
	LET f_node = f_doc.getDocumentElement()
	IF f_node IS NULL THEN
		DISPLAY "Failed to read:", l_fname
		EXIT PROGRAM
	END IF

	LET nl = f_node.selectByPath("//Form")
	IF nl.getLength() = 0 THEN
		DISPLAY "Not a Genero form!"
		RETURN
	END IF

	LET x = l_fname.getindexof(".", 1)
	IF x = 0 THEN
		LET l_outname = "t.per"
	ELSE
		IF os.path.exists(l_bakname) THEN
		LET l_outname = l_fname.substring(1, x)
		LET l_bakname = l_outname.append("per.njm")
		LET l_outname = l_outname.append("per")
		IF NOT os.path.exists(l_bakname) THEN
			IF NOT os.Path.rename(l_outname.trim(), l_bakname.trim()) THEN
				DISPLAY SFMT("Failed to backup %1! aborting.", l_outname.trim())
				EXIT PROGRAM
			END IF
			IF NOT os.path.chRwx(l_bakname.trim(), "256") THEN
				DISPLAY SFMT("Failed to chmod %1! aborting.", l_outname.trim())
				EXIT PROGRAM
			END IF
		END IF
	END IF

	DISPLAY "Opening ", l_outname.trim(), " for writing ,,."
	CALL chan.openFile(l_outname, "w")
	IF STATUS != 0 THEN
		DISPLAY "Error:", STATUS
		EXIT PROGRAM
	END IF
	CALL chan.setDelimiter("")

	CALL do_it(f_node, l_fname.subString(1, x - 1))

	DISPLAY "Closing ", l_outname.trim()
	CALL chan.close()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_it(st_node, fname)
	DEFINE st_node om.DomNode
	DEFINE fname STRING
	DEFINE x SMALLINT

	IF dbname IS NOT NULL AND dbname != " " THEN
		CALL out("SCHEMA " || dbname)
	END IF
	CALL out("")

	LET labno = 0
	CALL labtxt.clear()
	LET g_titl = ""
	CALL do_layout(st_node, FALSE) -- check just, don't process ?
	IF ver IS NOT NULL THEN
		CALL out("LAYOUT (TEXT=%\"\", STYLE=\"maint\", VERSION=\"" || ver || "\")")
	ELSE
		IF g_titl IS NULL THEN
			LET g_titl = fname
		END IF
		CALL out("LAYOUT (TEXT=%\"" || g_titl || "\", STYLE=\"maint\", VERSION=TIMESTAMP )")
	END IF
	CALL out("GRID")
	CALL out("{")
	CALL do_layout(st_node, TRUE)
	CALL out("}")
	CALL out("END -- GRID")

	IF dbname IS NOT NULL AND dbname != " " THEN
		CALL do_tabs(st_node)
		IF no_of_tabs > 0 THEN
			CALL out("TABLES")
			FOR x = 1 TO no_of_tabs
				CALL out(m_tabs[x])
			END FOR
		END IF
	END IF
	CALL out("")
	CALL out("ATTRIBUTES")
	IF conv_labs THEN
		FOR x = 1 TO labtxt.getLength()
			CALL out(
					"LABEL l"
							|| (x USING "<<<")
							|| " : lab"
							|| (x USING "<<<")
							|| ",TEXT=%\""
							|| labtxt[x]
							|| "\","
							|| labattr[x]
							|| ";")
		END FOR
		CALL out("")
	END IF
	CALL do_attr()
	CALL out("END")
	CALL out("")
	CALL out("INSTRUCTIONS")
	CALL do_recs(st_node)
	CALL out("END")

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION find_top_comments(l_source STRING) RETURNS()
	DEFINE l_line, l_tmp STRING

	LET per = base.Channel.create()
	DISPLAY "Opening ", l_source.trim(), " for reading,,."
	CALL per.openFile(l_source, "r")
	IF STATUS != 0 THEN
		DISPLAY "Error:", STATUS
		EXIT PROGRAM
	END IF
	CALL per.setDelimiter("")

	WHILE per.Read(l_line)
		IF l_line IS NOT NULL THEN
			LET l_tmp = UPSHIFT(l_line.trim())
			IF l_tmp.subString(1, 8) = "DATABASE" OR l_tmp.subString(1, 6) = "SCREEN" THEN
				EXIT WHILE
			END IF
			CALL out(l_line)
		END IF
	END WHILE

	DISPLAY "Closing ", l_source.trim()
	CALL per.close()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_layout(st_node, proc)
	DEFINE st_node om.DomNode
	DEFINE proc SMALLINT
	DEFINE n om.DomNode
	DEFINE nl om.NodeList
	DEFINE x SMALLINT

	LET nl = st_node.selectByPath("//Grid")
	IF nl.getLength() = 0 THEN
		DISPLAY "Error, can't find Gridnode!"
		RETURN
	ELSE
		DISPLAY "Outputting Grid"
		LET n = nl.item(1)
	END IF
	LET n = n.getFirstChild()

	WHILE n IS NOT NULL
--		DISPLAY n.getTagname()
		IF n.getTagname() = "Label" THEN
			IF n.getAttribute("posY") = 0 THEN
				LET g_titl = n.getAttribute("text")
				IF NOT proc THEN
					RETURN
				END IF
			ELSE
				IF proc THEN
					CALL do_lab(n)
				END IF
			END IF
		END IF
		IF proc THEN
			IF n.getTagname() = "FormField" THEN
				IF do_ff(n) THEN
					LET n = n.getNext()
					CONTINUE WHILE
				END IF
			END IF
			IF n.getTagname() = "Matrix" THEN
				IF do_ff(n) THEN
				END IF
			END IF
			IF n.getTagname() = "HLine" THEN
				CALL do_lab(n)
			END IF
		END IF
		LET n = n.getNext()
	END WHILE
	IF NOT proc THEN
		RETURN
	END IF
	FOR x = 1 TO max_scr
		CALL out(m_scr[x] CLIPPED)
	END FOR

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_lab(n)
	DEFINE n om.DomNode
	DEFINE txt STRING
	DEFINE l2, l_len, maxlen SMALLINT

	LET scr_x = n.getAttribute("posX") + 1
	LET scr_y = n.getAttribute("posY") + 1

	IF n.getTagName() = "HLine" THEN
		LET m_scr[scr_y][scr_x, scr_x + n.getAttribute("gridWidth")] =
				"--------------------------------------------------------------------------------"
		RETURN
	END IF

	LET txt = n.getAttribute("text")
	IF txt IS NULL THEN
		RETURN
	END IF
	CALL test_for_next_label(
			n, txt)
			RETURNING txt, l_len -- looking for 'Field   :'  type multi labels

	IF n.getTagName() = "Label" THEN
		LET l = n.getAttribute("gridWidth")
		IF l IS NULL OR l = 0 THEN
			LET l = txt.getLength()
		END IF
	END IF
	IF l_len IS NOT NULL AND l_len > 1 THEN
		LET l = l_len
	END IF
	DISPLAY "Label:", txt, " Width:", l
	IF conv_labs AND l > 0 THEN
		LET maxlen = 5
		IF labno < 9 THEN
			LET maxlen = 4
		END IF
		IF l > (maxlen - 1) THEN
			LET l2 = l - (maxlen - 1)
			LET labno = labtxt.getLength() + 1
			LET labtxt[labno] = txt
			LET txt = "[l" || (labno USING "<<<")
			LET l2 = l - txt.getLength()
			LET txt = txt || (l2 SPACES) || "]"

			IF n.getAttribute("style") THEN
				LET labattr[labno] = "STYLE='" || n.getAttribute("style") || "'"
			ELSE
				LET labattr[labno] = "STYLE='lab'"
			END IF
			IF n.getAttribute("justify") THEN
				LET labattr[labno] = labattr[labno].append(",JUSTIFY=" || n.getAttribute("justify"))
			ELSE
				LET labattr[labno] = labattr[labno].append(",JUSTIFY=RIGHT")
			END IF
		ELSE
			DISPLAY "Label not converted:", txt
		END IF
	END IF

	LET m_scr[scr_y][scr_x, scr_x + l] = txt

	IF scr_y > max_scr THEN
		LET max_scr = scr_y
	END IF

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_ff(ff)
	DEFINE ff, ty om.DomNode
	DEFINE f, a_h, a_s, y, x, t SMALLINT
	DEFINE config CHAR(200)
	DEFINE myTok base.StringTokenizer
	DEFINE myStr STRING

	LET ty = ff.getFirstChild()

	LET f = ff.getAttribute("fieldId")
	LET scr_x = ty.getAttribute("posX")
	LET scr_y = ty.getAttribute("posY") + 1

	DISPLAY "Processing:", ty.getTagName(), " Justify:", ty.getAttribute("justify")

	LET fields = fields + 1
	LET a_h = 0
	LET a_s = 1

	LET m_fields[fields].tb = ff.getAttribute("sqlTabName")
	LET m_fields[fields].nm = ff.getAttribute("colName")

	LET m_fields[fields].ty = UPSHIFT(ty.getTagName())

	IF ty.getTagName() = "Label" THEN
		LET m_fields[fields].ty = "LABEL"
	END IF

	LET myStr = ff.getAttribute("sqlType")
	IF ff.getAttribute("sqlTabName") = "formonly" AND myStr.getLength() > 0 THEN
		IF myStr.subString(1, 4) != "CHAR" THEN
			LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, " TYPE " || myStr
		END IF
	END IF

	IF ty.getTagName() = "ComboBox" THEN
		LET m_fields[fields].ty = "COMBOBOX"
		LET myStr = ff.getAttribute("include")
		LET myTok = base.StringTokenizer.create(myStr, "|")
		LET config = "'"
		LET config = config CLIPPED, myTok.nextToken()
		WHILE myTok.hasMoreTokens()
			LET config = config CLIPPED, "','"
			LET config = config CLIPPED, myTok.nextToken()
		END WHILE
		LET m_fields[fields].ar = ", ITEMS=(", config CLIPPED, "')"
	END IF

	IF ty.getTagName() = "RadioGroup" THEN
		LET m_fields[fields].ty = "RADIOGROUP"
		LET config = ty.getAttribute("config")
		LET m_fields[fields].ar = ", ITEMS=(('"
		LET x = LENGTH(m_fields[fields].ar) + 1
		FOR y = 1 TO LENGTH(config)
			CASE config[y]
				WHEN " "
				WHEN "{"
					LET m_fields[fields].ar[x] = "'"
					LET x = x + 1
					LET m_fields[fields].ar[x] = ","
					LET x = x + 1
					LET m_fields[fields].ar[x] = "'"
					LET x = x + 1
				WHEN "}"
					LET m_fields[fields].ar[x] = "'"
					LET x = x + 1
					LET m_fields[fields].ar[x] = "),"
					LET x = x + 1
					LET m_fields[fields].ar[x] = ","
					LET x = x + 1
					LET m_fields[fields].ar[x] = "("
					LET x = x + 1
					LET m_fields[fields].ar[x] = "'"
					LET x = x + 1
				OTHERWISE
					LET m_fields[fields].ar[x] = config[y]
					LET x = x + 1
			END CASE
		END FOR
		LET m_fields[fields].ar[x - 3, x] = ")    "
	END IF

	IF ty.getTagName() = "Button" THEN
		LET config = ff.getAttribute("colName")
		LET m_fields[fields].ty = "BUTTON"
		LET m_fields[fields].tb = NULL
		LET m_fields[fields].nm = ty.getAttribute("config")
		IF m_fields[fields].nm IS NULL OR m_fields[fields].nm = " " THEN
			LET m_fields[fields].nm = "fld", ff.getAttribute("fieldId")
		END IF
		LET m_fields[fields].ar = ", TEXT='", DOWNSHIFT(config) CLIPPED, "'"
	END IF

	IF ty.getTagName() = "CheckBox" THEN
		LET m_fields[fields].ty = "CHECKBOX"
		LET config = ty.getAttribute("config")
		LET m_fields[fields].ar = ", VALUECHECKED='", config[1], "'"
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", VALUEUNCHECKED='", config[3], "'"
		LET l = LENGTH(config)
		IF l > 6 THEN
			LET config = config[6, l - 1]
			LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", TEXT='", config CLIPPED, "'"
		END IF
	END IF

	IF ty.getTagName() = "ButtonEdit" THEN
		LET m_fields[fields].ty = "BUTTONEDIT"
		LET config = ty.getAttribute("config")
		IF config IS NULL THEN
			LET config = ty.getAttribute("action")
		END IF
		FOR y = 1 TO LENGTH(config)
			IF config[y] = "." THEN
				LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, " ,SCROLL"
			END IF
			IF config[y] = " " THEN
				LET config = config[y + 1, 100]
				EXIT FOR
			END IF
		END FOR
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", ACTION=", DOWNSHIFT(config) CLIPPED
	END IF

	IF ty.getTagName() = "Image" THEN
		LET m_fields[fields].ty = "BUTTON"
		LET m_fields[fields].tb = NULL
		LET config = ty.getAttribute("config")
		FOR y = 1 TO LENGTH(config)
			IF config[y] = "." THEN
				LET m_fields[fields].ar = ", IMAGE='", config[1, y - 1], "'"
			END IF
			IF config[y] = " " THEN
				LET config = config[y + 1, 100]
				EXIT FOR
			END IF
		END FOR
		LET m_fields[fields].nm = config
	END IF

	IF ty.getTagName() = "TextEdit" THEN
		LET a_h = ty.getAttribute("height") - 1
	END IF

	IF ty.getTagName() = "Canvas" THEN
		LET a_h = ty.getAttribute("height") - 1
	END IF

	IF ff.getAttribute("noEntry") = "1" THEN
		IF m_fields[fields].ty != "BUTTON" AND m_fields[fields].ty != "LABEL" THEN
			LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", NOENTRY"
		END IF
	END IF

	IF ff.getAttribute("justify") THEN
		LET m_fields[fields].ar =
				m_fields[fields].ar CLIPPED, ", JUSTIFY=" || ff.getAttribute("justify")
	END IF
	IF ff.getAttribute("required") = "1" THEN
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", REQUIRED"
	END IF

	IF ff.getAttribute("notNull") = "1" THEN
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", NOT NULL"
	END IF

	IF ty.getAttribute("comment") THEN
		LET m_fields[fields].ar =
				m_fields[fields].ar CLIPPED, ", COMMENT=%\"", ty.getAttribute("comment") CLIPPED, "\""
	END IF

	IF ty.getAttribute("defaultValue") THEN
		LET m_fields[fields].ar =
				m_fields[fields].ar CLIPPED, ", DEFAULT=\"", ty.getAttribute("defaultValue") CLIPPED, "\""
	END IF

	IF ty.getAttribute("autoNext") = "1" THEN
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", AUTONEXT"
	END IF

	IF m_fields[fields].ty != "BUTTON" AND m_fields[fields].ty != "LABEL" THEN
		IF ty.getAttribute("shift") = "up" THEN
			LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", UPSHIFT"
		END IF
		IF ty.getAttribute("shift") = "down" THEN
			LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", DOWNSHIFT"
		END IF
	END IF

	LET myStr = ff.getAttribute("defaultValue")
	IF myStr.getLength() > 0 THEN
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", DEFAULT=\"" || myStr || "\""
	END IF

	LET myStr = ty.getAttribute("picture")
	IF myStr.getLength() > 0 THEN
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", PICTURE=\"", myStr, "\""
	END IF

	LET myStr = ty.getAttribute("verify")
	IF myStr.getLength() > 0 THEN
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", VERIFY"
	END IF

	LET myStr = ff.getAttribute("include")
	IF myStr.getLength() > 0 THEN
		LET t = myStr.getIndexOf(":", 1)
		IF t > 0 THEN
			LET config = myStr.subString(1, t - 1) || " TO " || myStr.subString(t + 1, myStr.getLength())
		ELSE
			LET myTok = base.StringTokenizer.createExt(myStr, "|", "\\", TRUE)
			LET config = "'"
			LET config = config CLIPPED, myTok.nextToken()
			WHILE myTok.hasMoreTokens()
				LET config = config CLIPPED, "','"
				LET config = config CLIPPED, myTok.nextToken()
			END WHILE
			LET config = config CLIPPED || "'"
		END IF
		LET m_fields[fields].ar = m_fields[fields].ar CLIPPED, ", INCLUDE=(" || config CLIPPED || ")"
		DISPLAY "Include:", myStr, ":", config
	END IF

	IF ty.getAttribute("color") THEN
		LET m_fields[fields].ar =
				m_fields[fields].ar CLIPPED, ", STYLE='", ty.getAttribute("color") CLIPPED, "'"
	END IF

	IF ty.getAttribute("justify") THEN
		LET m_fields[fields].ar =
				m_fields[fields].ar CLIPPED, ", JUSTIFY=", ty.getAttribute("justify") CLIPPED
	END IF

	IF ff.getTagName() = "Matrix" THEN
		LET a_h = ff.getAttribute("pageSize") - 1
		LET a_s = ff.getAttribute("stepY")
		IF a_s IS NULL THEN
			LET a_s = 1
		END IF
		--DISPLAY "h:", ff.getAttribute("pageSize")," colname:",ff.getAttribute("colName")
	END IF

	LET l = ty.getAttribute("width")
	LET m_fields[fields].id = "f", f USING "<<<&"
	IF l = 1 THEN
		LET single = single + 1
		LET m_fields[fields].id = ASCII (96) + single
	END IF
	IF l = 2 THEN
		LET double1 = double1 + 1
		IF double1 > 26 THEN
			LET double1 = 1
			LET double2 = double2 + 1
		END IF
		LET m_fields[fields].id = NULL
		LET m_fields[fields].id[1] = ASCII (96) + double2
		LET m_fields[fields].id[2] = ASCII (96) + double1
	END IF
	LET config = m_fields[fields].id
	FOR y = scr_y TO scr_y + (a_h * a_s) STEP a_s
--		DISPLAY "Loop:",y," a_h:",a_h," a_s:",a_s," config:",config CLIPPED
		IF m_scr[y][scr_x] = "]" THEN
			LET m_scr[y][scr_x, scr_x + l] = "|", config CLIPPED
		ELSE
			LET m_scr[y][scr_x, scr_x + l] = "[", config CLIPPED
		END IF
		LET m_scr[y][scr_x + l + 1] = "]"
		IF ty.getTagName() = "TextEdit" THEN
			LET config = " "
		END IF
	END FOR
	IF y > max_scr THEN
		LET max_scr = y
	END IF

	RETURN TRUE

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_keys(st_node)
	DEFINE st_node om.DomNode
	DEFINE n om.DomNode
	DEFINE nl om.NodeList
	DEFINE x, x1 SMALLINT
	DEFINE accName STRING
	DEFINE accText STRING
	DEFINE tex CHAR(50)

	LET nl = st_node.selectByPath("//Action")
	FOR x = 1 TO nl.getLength()
		LET n = nl.item(x)
		LET accName = DOWNSHIFT(n.getAttribute("acceleratorName"))
		LET accText = n.getAttribute("text")
		CASE accName
			WHEN "esc"
				LET accName = "escape"
			WHEN "cr"
				LET accName = "return"
			WHEN "enter"
				LET accName = "return"
		END CASE
		IF accText IS NULL OR accText = " " THEN
			CONTINUE FOR
		END IF
		LET x1 = accText.getindexof("-", 1)
		IF x1 > 0 THEN
			LET tex = accText.trim()
			LET l = accText.getLength()
			IF tex[x1 + 1] = " " THEN
				LET tex = tex[1, x1 - 1], tex[x1 + 1, l]
			ELSE
				LET tex = tex[1, x1 - 1], " ", tex[x1 + 1, l]
			END IF
			LET accText = tex
		END IF
		FOR x1 = 1 TO no_of_keys
			IF key[x1] IS NULL OR (key[x1] = accName AND key_name[x1] = accText) THEN
				IF key[x1] IS NULL THEN
					LET key[x1] = accName.trim()
					LET key_name[x1] = accText.trim()
					LET no_of_keys = no_of_keys + 1
				END IF
				EXIT FOR
			END IF
		END FOR
	END FOR

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_recs(st_node)
	DEFINE st_node om.DomNode
	DEFINE n om.DomNode
	DEFINE nl, nl2 om.NodeList
	DEFINE x, x2 SMALLINT
	DEFINE tabn CHAR(30)
	DEFINE line STRING

	LET nl = st_node.selectByPath("//RecordView")
	FOR x = 1 TO nl.getLength()
		LET n = nl.item(x)
		LET tabn = n.getAttribute("tabName")
		FOR x2 = 1 TO no_of_tabs
			IF tabn = m_tabs[x2] THEN
				LET tabn = "formonly"
			END IF
		END FOR
		IF tabn != "formonly" THEN
			LET nl2 = n.selectByPath("//Link")
			IF nl2.getLength() > 0 THEN
				LET line = "SCREEN RECORD ", tabn CLIPPED, " ("
			END IF
			FOR x2 = 1 TO nl2.getLength()
				LET n = nl2.item(x2)
				CASE x2
--					WHEN 1
--						CALL out("		("||n.getAttribute("colName")||",")
					WHEN nl2.getLength()
						LET line = line.append(n.getAttribute("colName") || ")")
--						CALL out("			"||n.getAttribute("colName")||")")
					OTHERWISE
						LET line = line.append(n.getAttribute("colName") || ",")
--						CALL out("			"||n.getAttribute("colName")||",")
				END CASE
			END FOR
			IF line.getLength() > 0 THEN
				CALL out(line)
			END IF
		END IF
	END FOR

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_tabs(st_node)
	DEFINE st_node om.DomNode
	DEFINE n om.DomNode
	DEFINE nl om.NodeList
	DEFINE x, x1, x2 SMALLINT

	LET nl = st_node.selectByPath("//FormField")
	LET x1 = 1
	FOR x = 1 TO nl.getLength()
		LET n = nl.item(x)
		IF n.getAttribute("sqlTabName") != "formonly" THEN
--			DISPLAY "do_tabs:",x1,":",n.getAttribute("sqlTabName")
			FOR x2 = 1 TO x1
				IF m_tabs[x2] IS NULL OR m_tabs[x2] = n.getAttribute("sqlTabName") THEN
					IF m_tabs[x2] IS NULL THEN
						LET m_tabs[x2] = n.getAttribute("sqlTabName")
						LET x1 = x1 + 1
					END IF
					EXIT FOR
				END IF
			END FOR
		END IF
	END FOR

	LET nl = st_node.selectByPath("//Matrix")
	FOR x = 1 TO nl.getLength()
		LET n = nl.item(x)
		IF n.getAttribute("sqlTabName") != "formonly" THEN
--			DISPLAY "do_tabs:",x1,":",n.getAttribute("sqlTabName")
			FOR x2 = 1 TO x1
				IF m_tabs[x2] IS NULL OR m_tabs[x2] = n.getAttribute("sqlTabName") THEN
					IF m_tabs[x2] IS NULL THEN
						LET m_tabs[x2] = n.getAttribute("sqlTabName")
						LET x1 = x1 + 1
					END IF
					EXIT FOR
				END IF
			END FOR
		END IF
	END FOR

	LET no_of_tabs = x1 - 1
--	DISPLAY "Tables:",no_of_tabs

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION do_attr() RETURNS()
	DEFINE x SMALLINT
	DEFINE l_line STRING

	FOR x = 1 TO fields
		IF DOWNSHIFT(m_fields[x].tb) = "formonly" THEN
			LET m_fields[x].tb = UPSHIFT(m_fields[x].tb)
		END IF
		IF m_fields[x].tb IS NOT NULL THEN
			LET l_line =
					m_fields[x].ty CLIPPED,
					" ",
					m_fields[x].id CLIPPED,
					" = ",
					m_fields[x].tb CLIPPED,
					".",
					m_fields[x].nm CLIPPED,
					m_fields[x].ar CLIPPED,
					";"
		ELSE
			LET l_line =
					m_fields[x].ty CLIPPED,
					" ",
					m_fields[x].id CLIPPED,
					" : ",
					m_fields[x].nm CLIPPED,
					m_fields[x].ar CLIPPED,
					";"
		END IF
		CALL out(l_line)
	END FOR

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION out(l_line STRING) RETURNS()

--	DISPLAY line.trimright()
	CALL chan.write(l_line.trimright())

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION keyact(l_key STRING) RETURNS STRING
	DEFINE l_act STRING
	DEFINE nl om.NodeList
	DEFINE n om.domNode

	LET l_key = l_key.toLowerCase()
	LET nl = actions.selectByPath("//Rule[@key=\"" || l_key.trim() || "\"]")
	IF nl.getLength() > 0 THEN
		LET n = nl.Item(1)
		LET l_act = n.getAttribute("action")
	ELSE
		DISPLAY "Failed to found:", l_key
		RETURN l_key
	END IF

	RETURN l_act
END FUNCTION
--------------------------------------------------------------------------------
-- looking for 'Field   :'  type multi labels
FUNCTION test_for_next_label(n om.domNode, l_txt STRING) RETURNS(STRING, INT)
	DEFINE n1 om.domNode
	DEFINE l_len SMALLINT
	LET n1 = n.getNext()
	IF n1 IS NULL THEN
		RETURN l_txt, 0
	END IF
	IF n1.getTagName() != "Label" THEN
		RETURN l_txt, 0
	END IF
	IF n1.getAttribute("posY") != n.getAttribute("posY") THEN
		RETURN l_txt, 0
	END IF
	LET l_txt = l_txt.append(" ")
	LET l_txt = l_txt.append(n1.getAttribute("text"))
	LET l_len = n.getAttribute("posX")
	LET l_len = (n1.getAttribute("posX") - l_len) + LENGTH(n1.getAttribute("text"))
	DISPLAY "l_len:",
			l_len,
			" PosX1:",
			n.getAttribute("posX"),
			" PosX2:",
			n1.getAttribute("posX"),
			" TextLen:",
			LENGTH(n1.getAttribute("text"))

-- to avoid this label being processed twice
	CALL n1.removeAttribute("text")

	RETURN l_txt, l_len

END FUNCTION
