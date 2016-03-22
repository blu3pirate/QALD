require 'json'
require 'uri'
require 'multiset'
require 'mustache'

#################################################################

input_user = ARGV[0]
systemname = ARGV[1].nil? ? "" : ARGV[1]
config     = ARGV[2].nil? ? "" : ARGV[2]

template   = "../scripts/evaluation_result_html.mustache"

#################################################################


def read_answers(file)

    out = {}

    doc = JSON.parse(File.read(file))

    doc["questions"].each do |question|

      answers = []
      if question.key? "answers"
         question["answers"].each do |answer|
           bs = Multiset.new
           if answer.key? "results" and answer["results"].key? "bindings"
              answer["results"]["bindings"].each do |bind|
                b = Multiset.new
                bind.each { |_,value| b << normalize(value["value"]) }
                bs << b
              end
              answers << bs
           end
         end
      end

      out[question["id"]] = answers
    end

    return doc["dataset"]["id"], out
end

def normalize(answer)

    if answer =~ /\A\d+\z/
       return answer + ".0"
    else
       return URI.unescape(answer.strip)
    end
end

def compare_answers(answers_user,answers_gold)

    results = {}

    answers_gold.each do |id,gold|

      results[id] = { :total_gold => gold.length }

      if answers_user.key? id
         user = answers_user[id]
         results[id][:processed]  = true
         results[id][:total_user] = user.length
         results[id][:correct]    = (user.select {|x| gold.include? x}).length
      else
         results[id][:processed]  = false
      end
    end

  return results
end

def compute_results(results,answers_gold)

    breakdown = []

    sum_precision = 0
    sum_recall    = 0
    sum_f1        = 0

    sum_correct         = 0
    sum_total_gold_all  = 0
    sum_total_gold_proc = 0
    sum_total_user      = 0

    results.each do |id,comp|

      sum_total_gold_all += comp[:total_gold]

      if comp[:processed]
         sum_total_gold_proc += comp[:total_gold]
         sum_total_user      += comp[:total_user]
         sum_correct         += comp[:correct]

        # OUT OF SCOPE questions
        if comp[:total_gold] == 0
           if comp[:total_user] == 0
              precision = 1
              recall    = 1
              f1        = 1
           else
              precision = 0
              recall    = 0
              f1        = 0
           end
        # all other questions
        else
           if comp[:total_user] == 0
              precision = 1
           else
              precision = comp[:correct].to_f / comp[:total_user].to_f
           end
           recall = comp[:correct].to_f / comp[:total_gold].to_f
           f1 = if precision == 0 and recall == 0 then 0 else (2 * precision * recall) / (precision + recall) end
        end
      else 
        precision = 0
	recall    = 0
	f1        = 0
      end

      breakdown << { :id        => id,
                     :precision => precision,
                     :recall    => recall,
                     :f1        => f1 }

      sum_precision += precision
      sum_recall    += recall
      sum_f1        += f1
    end

    measures = { :breakdown => breakdown.sort_by { |x| x[:id] }, :processed => {}, :all => {} }

    ## Measures on processed questions only

    number_of_processed_questions = (results.select { |_,comp| comp[:processed] }).length

    micro_precision1 = if sum_total_user == 0 then 0 else sum_correct.to_f / sum_total_user.to_f end
    micro_recall1    = if sum_total_gold_proc == 0 then 0 else sum_correct.to_f / sum_total_gold_proc.to_f end
    micro_f1         = if micro_precision1 == 0 and micro_recall1 == 0 then 0 else (2 * micro_precision1 * micro_recall1) / (micro_precision1 + micro_recall1) end 

    measures[:processed][:micro] = { :precision => micro_precision1.round(2),
                                     :recall    => micro_recall1.round(2),
                                     :f1        => micro_f1.round(2) }

    macro_precision1 = if number_of_processed_questions == 0 then 0 else sum_precision.to_f / number_of_processed_questions.to_f end 
    macro_recall1    = if number_of_processed_questions == 0 then 0 else sum_recall.to_f / number_of_processed_questions.to_f end 
    macro_f1         = if number_of_processed_questions == 0 then 0 else sum_f1.to_f / number_of_processed_questions.to_f end 

    measures[:processed][:macro] = { :precision => macro_precision1.round(2), 
                                     :recall    => macro_recall1.round(2),
                                     :f1        => macro_f1.round(2) }

    ## Measures on all questions

    # Micro

    total_number_of_questions = answers_gold.keys.length

    micro_precision2 = if sum_total_user == 0 then 0 else sum_correct.to_f / sum_total_user.to_f end
    micro_recall2    = if sum_total_gold_all == 0 then 0 else sum_correct.to_f / sum_total_gold_all.to_f end
    micro_f2         = if micro_precision2 == 0 and micro_recall2 == 0 then 0 else (2 * micro_precision2 * micro_recall2) / (micro_precision2 + micro_recall2) end

    measures[:all][:micro] = { :precision => micro_precision2.round(2),
                               :recall    => micro_recall2.round(2),
                               :f1        => micro_f2.round(2) }

    # Macro
    macro_precision2 = if total_number_of_questions == 0 then 0 else sum_precision.to_f / total_number_of_questions.to_f end 
    macro_recall2    = if total_number_of_questions == 0 then 0 else sum_recall.to_f / total_number_of_questions.to_f end
    macro_f2         = if total_number_of_questions == 0 then 0 else sum_f1.to_f / total_number_of_questions.to_f end 

    measures[:all][:macro] = { :precision => macro_precision2.round(2),
                               :recall    => macro_recall2.round(2),
                               :f1        => macro_f2.round(2) }

    return measures
end


#################################################################

dataset, answers_user = read_answers(input_user)
_,       answers_gold = read_answers("../data/"+dataset+".json")

if answers_user.nil? 
   html = { :error => "Error when reading input file: " + input_user }
else

  results = compute_results(compare_answers(answers_user,answers_gold),answers_gold)

  html = Mustache.render(File.read(template),{ :gold    => dataset+".json",
                                               :system  => systemname,
                                               :config  => config,
                                               :time    => Time.now,
                                               :results => results })
end 

file = input_user + ".html"
File.write(file,html)
puts file
