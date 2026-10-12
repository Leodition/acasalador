# Atualização de pets e previsão de estoque

1. No SQL Editor do projeto Supabase utilizado pelo TeFalei, aplique primeiro `supabase/migrations/20261012_compras_estoque_pets.sql` se ainda não foi aplicada.
2. Execute todo o arquivo `supabase/migrations/20261013_pet_stock_forecast.sql`. A atualização é transacional e pode ser reaplicada. Não exclui os registros existentes e mantém as políticas RLS.
3. Recarregue o TeFalei. Os pets existentes e os novos passam a ter seções de estoque automaticamente. Se houver várias seções antigas do mesmo pet, elas são preservadas.
4. Cadastre o produto, quantidade, unidade, mínimo, consumo médio na mesma unidade, frequência em dias e antecedência do alerta. Ex.: 30 tapetes, consumo de 2 a cada 1 dia, alerta 3 dias antes.
5. Ao repor, use “Atualizar quantidade e consumo” para informar a quantidade real. A estimativa desconta o consumo desde a última atualização. O mínimo e a antecedência geram avisos visíveis ao abrir Compras e estoque.

Os alertas desta atualização são exibidos no aplicativo. Não há envio de push de estoque com o aplicativo fechado. Não é necessário alterar a data ISO no banco: as datas dos pets são apresentadas em DD/MM/AAAA.

Publicar a branch main não aplica a migração no Supabase. A execução no banco e a publicação do site devem ser verificadas separadamente.
