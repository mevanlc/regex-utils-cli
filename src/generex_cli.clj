(ns generex-cli
  (:gen-class)
  (:require [clojure.string :as str])
  (:import [com.mifmif.common.regex Generex]
           [java.nio ByteBuffer]
           [java.nio.charset CodingErrorAction StandardCharsets]
           [java.nio.file Files Path]))

(def ^:private program "generex")
(def ^:private version "generex 0.0.0 (Generex 1.0.2)")

(def ^:private top-help
  (str "Usage:\n"
       "  generex enumerate [OPTIONS] PATTERN\n"
       "  generex random [OPTIONS] PATTERN\n"
       "  generex first [OPTIONS] PATTERN\n"
       "  generex nth [OPTIONS] PATTERN INDEX\n"
       "  generex count [OPTIONS] PATTERN\n\n"
       "Pattern input:\n"
       "  PATTERN                    dk.brics automaton regex as one argument\n"
       "  -i, --input FILE           Read the complete regex; use - for stdin\n\n"
       "Generation options:\n"
       "  -n, --limit NUMBER         enumerate: maximum values; default 20\n"
       "  -n, --count NUMBER         random: number of values; default 1\n"
       "      --seed LONG            Seed java.util.Random reproducibly\n"
       "      --min-length NUMBER    Minimum random value length\n"
       "      --max-length NUMBER    Maximum random value length\n\n"
       "General options:\n"
       "  -h, --help                 Print help and exit\n"
       "  -V, --version              Print CLI and dependency versions\n"))

(defn- fail [status message]
  (throw (ex-info message {:status status})))

(defn- usage-error [message]
  (fail 2 message))

(defn- runtime-error [message]
  (fail 1 message))

(defn- option-spec [command option]
  (or ({"-h" [:help false]
        "--help" [:help false]
        "-i" [:input true]
        "--input" [:input true]} option)
      (case command
        "enumerate" ({"-n" [:limit true] "--limit" [:limit true]} option)
        "random" ({"-n" [:count true]
                    "--count" [:count true]
                    "--seed" [:seed true]
                    "--min-length" [:min-length true]
                    "--max-length" [:max-length true]} option)
        nil)))

(defn- parse-options [command arguments]
  (loop [remaining (seq arguments)
         options {:operands []}
         positional? false]
    (if-let [argument (first remaining)]
      (cond
        positional?
        (recur (next remaining) (update options :operands conj argument) true)

        (= argument "--")
        (recur (next remaining) options true)

        (str/starts-with? argument "-")
        (if-let [[key takes-value?] (option-spec command argument)]
          (do
            (when (contains? options key)
              (usage-error (str argument " may be supplied only once")))
            (if takes-value?
              (if-let [value (second remaining)]
                (recur (nnext remaining) (assoc options key value) false)
                (usage-error (str argument " requires a value")))
              (recur (next remaining) (assoc options key true) false)))
          (usage-error (str "unknown option " argument)))

        :else
        (recur (next remaining) (update options :operands conj argument) false))
      options)))

(defn- parse-integer [value label minimum maximum]
  (let [parsed (parse-long value)]
    (when (or (nil? parsed) (< parsed minimum) (> parsed maximum))
      (usage-error (format "%s must be an integer from %d through %d" label minimum maximum)))
    parsed))

(defn- decode-utf8 [bytes description]
  (try
    (let [decoder (doto (.newDecoder StandardCharsets/UTF_8)
                    (.onMalformedInput CodingErrorAction/REPORT)
                    (.onUnmappableCharacter CodingErrorAction/REPORT))]
      (str (.decode decoder (ByteBuffer/wrap bytes))))
    (catch Exception error
      (runtime-error (str description " is not valid UTF-8: " (.getMessage error))))))

(defn- read-pattern-file [pathname]
  (try
    (decode-utf8
     (if (= pathname "-")
       (.readAllBytes System/in)
       (Files/readAllBytes (Path/of pathname (make-array String 0))))
     "pattern input")
    (catch clojure.lang.ExceptionInfo error
      (throw error))
    (catch Exception error
      (runtime-error (str "cannot read pattern input " (pr-str pathname) ": "
                          (.getMessage error))))))

(defn- pattern-and-operands [options extra-count]
  (let [operands (:operands options)
        input (:input options)]
    (cond
      input
      (do
        (when-not (= (count operands) extra-count)
          (usage-error (if (zero? extra-count)
                         "PATTERN and --input are mutually exclusive"
                         "--input requires exactly one INDEX operand")))
        [(read-pattern-file input) operands])

      (= (count operands) (inc extra-count))
      [(first operands) (subvec (vec operands) 1)]

      :else
      (usage-error (if (zero? extra-count)
                     "provide exactly one PATTERN or --input FILE"
                     "provide PATTERN and INDEX, or --input FILE and INDEX")))))

(defn- json-string [value]
  (let [output (StringBuilder.)]
    (.append output \")
    (doseq [character value]
      (case character
        \" (.append output "\\\"")
        \\ (.append output "\\\\")
        \backspace (.append output "\\b")
        \formfeed (.append output "\\f")
        \newline (.append output "\\n")
        \return (.append output "\\r")
        \tab (.append output "\\t")
        (if (< (int character) 32)
          (.append output (format "\\u%04x" (int character)))
          (.append output character))))
    (.append output \")
    (str output)))

(defn- emit-value [value]
  (println (str "{\"value\":" (json-string value) "}")))

(defn- build-generex [pattern]
  (try
    (Generex. pattern)
    (catch Throwable error
      (runtime-error (str "cannot build generator: "
                          (or (.getMessage error) (.getName (class error))))))))

(defn- run-enumerate [options]
  (let [[pattern _] (pattern-and-operands options 0)
        limit (parse-integer (or (:limit options) "20") "--limit" 0 Integer/MAX_VALUE)
        iterator (.iterator (build-generex pattern))]
    (loop [remaining limit]
      (when (and (pos? remaining) (.hasNext iterator))
        (emit-value (str (.next iterator)))
        (recur (dec remaining))))))

(defn- random-value [generator options]
  (let [minimum (when-let [value (:min-length options)]
                  (parse-integer value "--min-length" 0 Integer/MAX_VALUE))
        maximum (when-let [value (:max-length options)]
                  (parse-integer value "--max-length" 0 Integer/MAX_VALUE))]
    (when (and minimum maximum (> minimum maximum))
      (usage-error "--min-length must not exceed --max-length"))
    (cond
      maximum (.random generator (int (or minimum 0)) (int maximum))
      minimum (.random generator (int minimum))
      :else (.random generator))))

(defn- run-random [options]
  (let [[pattern _] (pattern-and-operands options 0)
        count (parse-integer (or (:count options) "1") "--count" 0 Integer/MAX_VALUE)
        generator (build-generex pattern)]
    (when-let [value (:seed options)]
      (.setSeed generator (parse-integer value "--seed" Long/MIN_VALUE Long/MAX_VALUE)))
    (dotimes [_ count]
      (emit-value (random-value generator options)))))

(defn- run-first [options]
  (let [[pattern _] (pattern-and-operands options 0)]
    (emit-value (.getFirstMatch (build-generex pattern)))))

(defn- run-nth [options]
  (let [[pattern operands] (pattern-and-operands options 1)
        index (parse-integer (first operands) "INDEX" 1 Integer/MAX_VALUE)]
    (emit-value (.getMatchedString (build-generex pattern) (int index)))))

(defn- run-count [options]
  (let [[pattern _] (pattern-and-operands options 0)
        generator (build-generex pattern)]
    (if (.isInfinite generator)
      (println "infinite")
      (println (.matchedStringsSize generator)))))

(defn- run-command [command arguments]
  (when-not (#{"enumerate" "random" "first" "nth" "count"} command)
    (usage-error (str "unknown command " command)))
  (let [options (parse-options command arguments)]
    (if (:help options)
      (print top-help)
      (case command
        "enumerate" (run-enumerate options)
        "random" (run-random options)
        "first" (run-first options)
        "nth" (run-nth options)
        "count" (run-count options)))))

(defn -main [& arguments]
  (try
    (cond
      (= arguments '("--help")) (print top-help)
      (= arguments '("-h")) (print top-help)
      (= arguments '("--version")) (println version)
      (= arguments '("-V")) (println version)
      (empty? arguments) (usage-error "a command is required")
      :else (run-command (first arguments) (rest arguments)))
    (catch clojure.lang.ExceptionInfo error
      (let [status (or (:status (ex-data error)) 1)]
        (binding [*out* *err*]
          (println (str program ": " (.getMessage error)))
          (when (= status 2)
            (println (str "Try '" program " --help' for usage."))))
        (System/exit status)))
    (catch Throwable error
      (binding [*out* *err*]
        (println (str program ": " (or (.getMessage error) (.getName (class error))))))
      (System/exit 1))))
