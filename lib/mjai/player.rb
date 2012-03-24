require "ostruct"

require "mjai/pai"
require "mjai/tenpai_analysis"


module Mjai
    
    class Player
        
        attr_reader(:id)
        attr_reader(:tehais)  # 手牌
        attr_reader(:furos)  # 副露
        attr_reader(:ho)  # 河 (鳴かれた牌を含まない)
        attr_reader(:sutehais)  # 捨牌 (鳴かれた牌を含む)
        attr_reader(:extra_anpais)  # sutehais以外のこのプレーヤに対する安牌
        attr_reader(:reach_ho_index)
        attr_reader(:attributes)
        attr_accessor(:name)
        attr_accessor(:game)
        attr_accessor(:points)
        
        def anpais
          return @sutehais + @extra_anpais
        end
        
        def reach?
          return @reach
        end
        
        def update_state(action)
          
          if @game.previous_action &&
              @game.previous_action.type == :dahai &&
              @game.previous_action.actor != self &&
              action.type != :hora
            @extra_anpais.push(@game.previous_action.pai)
          end
          
          case action.type
            when :start_game
              @id = action.id
              @name = action.names[@id] if action.names
              @points = 25000
              @attributes = OpenStruct.new()
            when :start_kyoku
              @tehais = []
              @furos = []
              @ho = []
              @sutehais = []
              @extra_anpais = []
              @reach = false
              @reach_ho_index = nil
          end
          
          if action.actor == self
            case action.type
              when :haipai
                @tehais = action.pais.sort()
              when :tsumo
                @tehais.push(action.pai)
              when :dahai
                delete_tehai(action.pai)
                @tehais.sort!()
                @ho.push(action.pai)
                @sutehais.push(action.pai)
                @extra_anpais.clear() if !@reach
              when :chi, :pon, :daiminkan, :ankan
                for pai in action.consumed
                  delete_tehai(pai)
                end
                @furos.push(Furo.new({
                  :type => action.type,
                  :taken => action.pai,
                  :consumed => action.consumed,
                  :target => action.target,
                }))
              when :kakan
                delete_tehai(action.pai)
                pon_index = @furos.index(){ |f| f.type == :pon && f.taken.same_symbol?(action.pai) }
                raise("should not happen") if !pon_index
                @furos[pon_index] = Furo.new({
                  :type => :kakan,
                  :taken => @furos[pon_index].taken,
                  :consumed => @furos[pon_index].consumed + [action.pai],
                  :target => @furos[pon_index].target,
                })
              when :reach_accepted
                @reach = true
                @reach_ho_index = @ho.size - 1
                @points -= 1000
            end
          end
          
          if action.target == self
            case action.type
              when :chi, :pon, :daiminkan, :ankan
                pai = @ho.pop()
                raise("should not happen") if pai != action.pai
            end
          end
          
        end
        
        def jikaze
          if @game.oya
            return Pai.new("t", 1 + (4 + @id - @game.oya.id) % 4)
          else
            return nil
          end
        end
        
        def tenpai?
          return ShantenAnalysis.new(@tehais, 0).shanten <= 0
        end
        
        def furiten?
          return false if @tehais.size % 3 != 1
          return false if @tehais.include?(Pai::UNKNOWN)
          tenpai_info = TenpaiAnalysis.new(@tehais)
          return false if !tenpai_info.tenpai?
          anpais = self.anpais
          return tenpai_info.waited_pais.any?(){ |pai| anpais.include?(pai) }
        end
        
        def can_reach?(shanten_analysis = nil)
          shanten_analysis ||= ShantenAnalysis.new(@tehais, 0)
          return @game.current_action.type == :tsumo &&
              @game.current_action.actor == self &&
              shanten_analysis.shanten <= 0 &&
              @furos.empty? &&
              !@reach &&
              self.game.num_pipais >= 4
        end
        
        def can_hora?(shanten_analysis = nil)
          action = @game.current_action
          if action.type == :tsumo && action.actor == self
            hora_type = :tsumo
            hais = @tehais
          elsif action.type == :dahai && action.actor != self
            hora_type = :ron
            hais = @tehais + [action.pai]
          else
            return false
          end
          shanten_analysis ||= ShantenAnalysis.new(hais, -1)
          # TODO check yaku
          return shanten_analysis.shanten == -1 &&
              (hora_type == :tsumo || !self.furiten?)
        end
        
        def possible_furo_actions
          # TODO Consider red pai
          action = @game.current_action
          if (action.type != :dahai || action.actor == self) ||
              @reach ||
              @game.num_pipais < 4
            return []
          end
          result = []
          if @tehais.select(){ |pai| pai == action.pai }.size >= 3
            result.push(create_action({
              :type => :daiminkan,
              :pai => action.pai,
              :consumed => [action.pai] * 3,
              :target => action.actor
            }))
          elsif @tehais.select(){ |pai| pai == action.pai }.size >= 2
            result.push(create_action({
              :type => :pon,
              :pai => action.pai,
              :consumed => [action.pai] * 2,
              :target => action.actor
            }))
          elsif (action.actor.id + 1) % 4 == self.id && action.pai.type != "t"
            for i in 0...3
              consumed = (((-i)...(-i + 3)).to_a() - [0]).map() do |j|
                Pai.new(action.pai.type, action.pai.number + j)
              end
              if consumed.all?(){ |pai| @tehais.index(pai) }
                result.push(create_action({
                  :type => :chi,
                  :pai => action.pai,
                  :consumed => consumed,
                  :target => action.actor,
                }))
              end
            end
          end
          return result
        end
        
        def context
          return Context.new({
            :oya => self == self.game.oya,
            :bakaze => self.game.bakaze,
            :jikaze => self.jikaze,
            :doras => self.game.doras,
            :uradoras => [],  # TODO
            :reach => self.reach?,
            :double_reach => false,  # TODO
            :ippatsu => false,  # TODO
            :rinshan => false,  # TODO
            :haitei => self.game.num_pipais == 0,
            :first_turn => false,  # TODO
            :chankan => false,  # TODO
          })
        end
        
        def delete_tehai(pai)
          pai_index = @tehais.index(pai) || @tehais.index(Pai::UNKNOWN)
          raise("trying to delete %p which is not in tehais: %p" % [pai, @tehais]) if !pai_index
          @tehais.delete_at(pai_index)
        end
        
        def create_action(params = {})
          return Action.new({:actor => self}.merge(params))
        end
        
        def inspect
          return "\#<%p:%d>" % [self.class, self.id]
        end
        
    end
    
end
