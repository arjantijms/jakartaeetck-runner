/*
 *    DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
 *
 *    Copyright (c) [2019] Payara Foundation and/or its affiliates. All rights reserved.
 *
 *    The contents of this file are subject to the terms of either the GNU
 *    General Public License Version 2 only ("GPL") or the Common Development
 *    and Distribution License("CDDL") (collectively, the "License").  You
 *    may not use this file except in compliance with the License.  You can
 *    obtain a copy of the License at
 *    https://github.com/payara/Payara/blob/master/LICENSE.txt
 *    See the License for the specific
 *    language governing permissions and limitations under the License.
 *
 *    When distributing the software, include this License Header Notice in each
 *    file and include the License file at glassfish/legal/LICENSE.txt.
 *
 *    GPL Classpath Exception:
 *    The Payara Foundation designates this particular file as subject to the "Classpath"
 *    exception as provided by the Payara Foundation in the GPL Version 2 section of the License
 *    file that accompanied this code.
 *
 *    Modifications:
 *    If applicable, add the following below the License Header, with the fields
 *    enclosed by brackets [] replaced by your own identifying information:
 *    "Portions Copyright [year] [name of copyright owner]"
 *
 *    Contributor(s):
 *    If you wish your version of this file to be governed by only the CDDL or
 *    only the GPL Version 2, indicate your decision by adding "[Contributor]
 *    elects to include this software in this distribution under the [CDDL or GPL
 *    Version 2] license."  If you don't indicate a single choice of license, a
 *    recipient has the option to distribute your version of this file under
 *    either the CDDL, the GPL Version 2 or to extend the choice of license to
 *    its licensees as provided above.  However, if you add GPL Version 2 code
 *    and therefore, elected the GPL Version 2 license, then the option applies
 *    only if the new code is made subject to such option by the copyright
 *    holder.
 */

package fish.payara.internal.tcksummarizer;

import org.xml.sax.Attributes;

import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public class TestCase {
    public String failure;
    String name;
    String className;
    Integer time;
    String status;
    String output;
    private TermVector vector;
    private List<String> terms = new ArrayList<>();
    ZonedDateTime start;
    ZonedDateTime end;
    String log;
    StringBuilder serverLog;

    public TestCase(Attributes attributes) {
        name = attributes.getValue("name");
        className = attributes.getValue("classname");
        if (attributes.getIndex("time") >= 0) {
            time = Integer.parseInt(attributes.getValue("time"));
        }
        status = attributes.getValue("status");
    }

    public void parseOutput(String text) {
        this.output = text;
        JTRParser parser = new JTRParser(new Handler());
        parser.parse(text);
    }

    @Override
    public String toString() {
        return className + '#' + name;
    }

    public void appendServerLog(String entry) {
        if (serverLog == null) {
            serverLog = new StringBuilder();
        } else {
            serverLog.append("\n");
        }
        serverLog.append(entry);
        // and parse tokens of the log into terms
        String body = entry.substring(entry.indexOf("[[") + 2, entry.lastIndexOf("]]"));
        terms.addAll(Arrays.asList(body.split("\\W+")));
    }

    public boolean hasServerLog() {
        return serverLog != null && serverLog.length() > 0;
    }

    public String getServerLog() {
        return serverLog.toString();
    }

    TermVector getVector() {
        if (vector == null) {
            vector = new TermVector(terms);
        }
        return vector;
    }


    class Handler extends JTRParser.StatelessHandler {
        List<String> terms = new ArrayList<>();
        @Override
        protected void line(String section, String subSection, String line) {
            if ("section:TestRun".equals(section) && subSection != null && subSection.startsWith("log:")) {
                extractTerms(trimTimestamp(line));
            }
            if ("testresult".equals(section) && subSection == null) {
                if (line.startsWith("start")) {
                    start = parseDateLine(line);
                }
                if (line.startsWith("end")) {
                    end = parseDateLine(line);
                }
            }
        }

        private void extractTerms(String line) {
            log = log == null ? line : log +"\n" + line;
            terms.addAll(Arrays.asList(line.split("\\W+")));
        }

        @Override
        public void finish() {
            TestCase.this.terms.addAll(terms);
        }
    }

    final static DateTimeFormatter JTR_TIMESTAMP_FORMAT = DateTimeFormatter
            .ofPattern("EEE MMM dd HH:mm:ss zzz yyy").withLocale(Locale.ENGLISH);

    static ZonedDateTime parseDateLine(String line) {
        line = line.replaceFirst("^[^=]+=", "").replace("\\:",":");
        return ZonedDateTime.parse(line, JTR_TIMESTAMP_FORMAT);
    }

    private static String trimTimestamp(String line) {
        // Jul 22, 2019 11:01:41 AM
        // 07-22-2019 11:01:41:
        // Let's just trim everything before something looking like time
        return line.replaceFirst("^.+\\d\\d:\\d\\d:\\d\\d\\W+", "");
    }


}
